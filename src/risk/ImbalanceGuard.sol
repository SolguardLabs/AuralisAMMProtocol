// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { FullMath } from "../libraries/FullMath.sol";
import {
    AuralisCastOverflow,
    AuralisImbalanceExceeded,
    AuralisInvalidConfiguration,
    AuralisPoolNotInitialized,
    AuralisReserveBelowMinimum,
    AuralisUnauthorized,
    AuralisZeroAddress
} from "../types/AuralisErrors.sol";
import { PoolRiskConfig, RiskStatus } from "../types/AuralisTypes.sol";
import { Ownable2Step } from "../utils/Ownable2Step.sol";

/// @title Auralis reserve imbalance guard
/// @notice Enforces per-pool reserve bands relative to the ratio established at first mint.
/// @dev All checks operate on active virtual reserves supplied by the calling pool.
contract ImbalanceGuard is Ownable2Step {
    /// @notice Emitted when default limits used by newly initialized pools change.
    event DefaultRiskConfigUpdated(uint24 maximumImbalancePpm, uint112 minimumActiveReserve);

    /// @notice Emitted when a pool receives an immutable initial reserve-ratio anchor.
    event PoolAnchorInitialized(
        address indexed pool, uint112 anchorReserve0, uint112 anchorReserve1, uint32 initializedAt
    );

    /// @notice Emitted when a pool-specific risk policy is installed.
    event PoolRiskConfigUpdated(
        address indexed pool, uint24 maximumImbalancePpm, uint112 minimumActiveReserve, bool custom
    );

    uint256 public constant PPM = 1_000_000;
    uint256 private constant Q96 = 1 << 96;

    /// @notice Compact initial ratio recorded for a pool.
    struct PoolAnchor {
        uint112 reserve0;
        uint112 reserve1;
        uint32 initializedAt;
    }

    /// @notice Limits copied by pools that do not have an explicit override.
    PoolRiskConfig public defaultRiskConfig;

    mapping(address pool => PoolAnchor anchor) private _anchors;
    mapping(address pool => PoolRiskConfig configuration) private _poolConfigs;
    mapping(address pool => bool configured) private _hasCustomConfig;

    /// @param initialOwner Account authorized to maintain risk limits.
    constructor(
        address initialOwner
    ) Ownable2Step(initialOwner) {
        defaultRiskConfig =
            PoolRiskConfig({ maximumImbalancePpm: 250_000, minimumActiveReserve: 1000 });
    }

    /// @notice Changes the policy copied by pools without an override.
    function setDefaultRiskConfig(
        PoolRiskConfig calldata configuration
    ) external onlyOwner {
        _validateConfiguration(configuration);
        defaultRiskConfig = configuration;
        emit DefaultRiskConfigUpdated(
            configuration.maximumImbalancePpm, configuration.minimumActiveReserve
        );
    }

    /// @notice Sets or replaces the limits for one pool without changing its ratio anchor.
    function setPoolRiskConfig(
        address pool,
        PoolRiskConfig calldata configuration
    ) external onlyOwner {
        if (pool == address(0)) revert AuralisZeroAddress();
        _validateConfiguration(configuration);
        _poolConfigs[pool] = configuration;
        _hasCustomConfig[pool] = true;
        emit PoolRiskConfigUpdated(
            pool, configuration.maximumImbalancePpm, configuration.minimumActiveReserve, true
        );
    }

    /// @notice Removes an override so a pool follows the current defaults.
    function clearPoolRiskConfig(
        address pool
    ) external onlyOwner {
        delete _poolConfigs[pool];
        _hasCustomConfig[pool] = false;
        PoolRiskConfig memory configuration = defaultRiskConfig;
        emit PoolRiskConfigUpdated(
            pool, configuration.maximumImbalancePpm, configuration.minimumActiveReserve, false
        );
    }

    /// @notice Records the active-reserve ratio produced by a pool's first mint.
    /// @dev A pool may initialize itself; the owner may initialize a pool during deployment.
    function initializePool(
        address pool,
        uint256 virtualReserve0,
        uint256 virtualReserve1
    ) external {
        if (pool == address(0)) revert AuralisZeroAddress();
        if (msg.sender != pool && msg.sender != owner()) revert AuralisUnauthorized(msg.sender);
        if (_anchors[pool].initializedAt != 0) revert AuralisInvalidConfiguration();
        if (virtualReserve0 == 0 || virtualReserve1 == 0) {
            revert AuralisReserveBelowMinimum(0, 1);
        }
        if (virtualReserve0 > type(uint112).max) {
            revert AuralisCastOverflow(virtualReserve0, type(uint112).max);
        }
        if (virtualReserve1 > type(uint112).max) {
            revert AuralisCastOverflow(virtualReserve1, type(uint112).max);
        }

        // Both values were explicitly bounded above before these narrowing conversions.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint112 anchorReserve0 = uint112(virtualReserve0);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint112 anchorReserve1 = uint112(virtualReserve1);
        uint32 initializedAt = uint32(block.timestamp);
        _anchors[pool] = PoolAnchor({
            reserve0: anchorReserve0, reserve1: anchorReserve1, initializedAt: initializedAt
        });
        emit PoolAnchorInitialized(pool, anchorReserve0, anchorReserve1, initializedAt);
    }

    /// @notice Reverts unless active virtual reserves satisfy the pool's policy.
    /// @return imbalancePpm Symmetric ratio drift from the first-mint anchor.
    function checkVirtualReserves(
        address pool,
        uint256 virtualReserve0,
        uint256 virtualReserve1
    ) external view returns (uint256 imbalancePpm) {
        PoolAnchor memory anchor = _anchors[pool];
        if (anchor.initializedAt == 0) revert AuralisPoolNotInitialized();
        PoolRiskConfig memory configuration = riskConfig(pool);
        if (virtualReserve0 < configuration.minimumActiveReserve) {
            revert AuralisReserveBelowMinimum(virtualReserve0, configuration.minimumActiveReserve);
        }
        if (virtualReserve1 < configuration.minimumActiveReserve) {
            revert AuralisReserveBelowMinimum(virtualReserve1, configuration.minimumActiveReserve);
        }
        (,, imbalancePpm) = _normalize(virtualReserve0, virtualReserve1, anchor);
        if (imbalancePpm > configuration.maximumImbalancePpm) {
            revert AuralisImbalanceExceeded(imbalancePpm, configuration.maximumImbalancePpm);
        }
    }

    /// @notice Previews a reserve pair without reverting for a rejected policy result.
    function evaluate(
        address pool,
        uint256 virtualReserve0,
        uint256 virtualReserve1
    ) external view returns (RiskStatus memory status) {
        PoolAnchor memory anchor = _anchors[pool];
        PoolRiskConfig memory configuration = riskConfig(pool);
        status.minimumReserve = configuration.minimumActiveReserve;
        status.maximumImbalancePpm = configuration.maximumImbalancePpm;
        status.initialized = anchor.initializedAt != 0;
        if (!status.initialized) return status;

        (status.normalizedReserve0, status.normalizedReserve1, status.imbalancePpm) =
            _normalize(virtualReserve0, virtualReserve1, anchor);
        status.accepted = virtualReserve0 >= configuration.minimumActiveReserve
            && virtualReserve1 >= configuration.minimumActiveReserve
            && status.imbalancePpm <= configuration.maximumImbalancePpm;
    }

    /// @notice Returns the effective policy for `pool`.
    function riskConfig(
        address pool
    ) public view returns (PoolRiskConfig memory configuration) {
        configuration = _hasCustomConfig[pool] ? _poolConfigs[pool] : defaultRiskConfig;
    }

    /// @notice Returns a pool's immutable first-mint anchor.
    function poolAnchor(
        address pool
    ) external view returns (PoolAnchor memory) {
        return _anchors[pool];
    }

    /// @notice Returns token1 per token0 at the anchor in Q128 fixed-point form.
    function anchorRatioX128(
        address pool
    ) external view returns (uint256 ratioX128) {
        PoolAnchor memory anchor = _anchors[pool];
        if (anchor.initializedAt == 0) revert AuralisPoolNotInitialized();
        ratioX128 = FullMath.mulDiv(anchor.reserve1, 1 << 128, anchor.reserve0);
    }

    function _normalize(
        uint256 virtualReserve0,
        uint256 virtualReserve1,
        PoolAnchor memory anchor
    ) internal pure returns (uint256 normalized0, uint256 normalized1, uint256 imbalancePpm) {
        normalized0 = FullMath.mulDiv(virtualReserve0, Q96, anchor.reserve0);
        normalized1 = FullMath.mulDiv(virtualReserve1, Q96, anchor.reserve1);
        uint256 total = normalized0 + normalized1;
        if (total < normalized0) revert AuralisCastOverflow(total, type(uint256).max);
        if (total == 0) return (normalized0, normalized1, 0);
        uint256 difference =
            normalized0 > normalized1 ? normalized0 - normalized1 : normalized1 - normalized0;
        imbalancePpm = FullMath.mulDiv(difference, PPM, total);
    }

    function _validateConfiguration(
        PoolRiskConfig calldata configuration
    ) internal pure {
        if (
            configuration.maximumImbalancePpm == 0 || configuration.maximumImbalancePpm > PPM
                || configuration.minimumActiveReserve == 0
        ) revert AuralisInvalidConfiguration();
    }
}
