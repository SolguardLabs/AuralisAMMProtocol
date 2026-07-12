// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IAuralisFeeController } from "../interfaces/IAuralisFeeController.sol";
import { FullMath } from "../libraries/FullMath.sol";
import { Ownable2Step } from "../utils/Ownable2Step.sol";

/// @dev Optional extension implemented by Auralis-compatible volatility oracles.
interface IAuralisVolatilitySource {
    function volatility(
        uint32 secondsAgo
    ) external view returns (uint256 volatilityPpm);
}

/// @title Auralis dynamic fee controller
/// @notice Quotes swap fees from trade size, post-trade imbalance and observed volatility.
/// @dev Every fee and normalized risk input uses parts per million (ppm).
contract DynamicFeeController is IAuralisFeeController, Ownable2Step {
    /// @notice Reverts when a ppm value exceeds one hundred percent.
    error InvalidPpmValue(uint256 value);

    /// @notice Reverts when the configured fee bounds are inconsistent.
    error InvalidFeeBounds(uint24 minimumFee, uint24 baseFee, uint24 maximumFee);

    /// @notice Reverts when an address required for configuration is zero.
    error ZeroAddress();

    /// @notice Reverts when either reserve forming a ratio anchor is zero.
    error InvalidAnchor();

    /// @notice Emitted after the global fee curve changes.
    event FeeParametersUpdated(
        uint24 minimumFee,
        uint24 baseFee,
        uint24 maximumFee,
        uint24 sizeCoefficient,
        uint24 imbalanceCoefficient,
        uint24 volatilityCoefficient
    );

    /// @notice Emitted after the protocol share of swap fees changes.
    event ProtocolFeeShareUpdated(uint24 previousShare, uint24 newShare);

    /// @notice Emitted after a pool receives an anchor and optional volatility source.
    event PoolConfigurationUpdated(
        address indexed pool,
        address indexed oracle,
        uint128 anchorReserve0,
        uint128 anchorReserve1,
        uint32 volatilityWindow,
        bool oracleEnabled
    );

    /// @notice One million parts represents one hundred percent.
    uint24 public constant override FEE_DENOMINATOR = 1_000_000;

    /// @notice Hard upper bound accepted for a volatility sample.
    uint24 public constant MAX_NORMALIZED_VOLATILITY = 1_000_000;

    /// @notice Per-pool inputs used to measure price-ratio drift and volatility.
    struct PoolConfiguration {
        address oracle;
        uint128 anchorReserve0;
        uint128 anchorReserve1;
        uint32 volatilityWindow;
        bool oracleEnabled;
    }

    /// @inheritdoc IAuralisFeeController
    uint24 public override minimumFee;

    /// @inheritdoc IAuralisFeeController
    uint24 public override maximumFee;

    /// @notice Fee charged before risk-dependent additions, in ppm.
    uint24 public baseFee;

    /// @notice Multiplier applied to normalized input size, in ppm.
    uint24 public sizeCoefficient;

    /// @notice Multiplier applied to normalized reserve-ratio drift, in ppm.
    uint24 public imbalanceCoefficient;

    /// @notice Multiplier applied to oracle volatility, in ppm.
    uint24 public volatilityCoefficient;

    /// @inheritdoc IAuralisFeeController
    uint24 public override protocolFeeShare;

    /// @notice Pool-specific risk configuration.
    mapping(address pool => PoolConfiguration configuration) public poolConfigurations;

    /// @param initialOwner Account authorized to maintain fee parameters.
    constructor(
        address initialOwner
    ) Ownable2Step(initialOwner) {
        minimumFee = 500;
        baseFee = 3000;
        maximumFee = 30_000;
        sizeCoefficient = 20_000;
        imbalanceCoefficient = 40_000;
        volatilityCoefficient = 25_000;
        protocolFeeShare = 100_000;
    }

    /// @inheritdoc IAuralisFeeController
    function owner() public view override(IAuralisFeeController, Ownable2Step) returns (address) {
        return Ownable2Step.owner();
    }

    /// @notice Replaces the global dynamic fee curve.
    /// @param newMinimumFee Lowest quote the controller may return.
    /// @param newBaseFee Fee before dynamic additions.
    /// @param newMaximumFee Highest quote the controller may return.
    /// @param newSizeCoefficient Weight assigned to normalized trade size.
    /// @param newImbalanceCoefficient Weight assigned to post-trade ratio drift.
    /// @param newVolatilityCoefficient Weight assigned to oracle volatility.
    function setFeeParameters(
        uint24 newMinimumFee,
        uint24 newBaseFee,
        uint24 newMaximumFee,
        uint24 newSizeCoefficient,
        uint24 newImbalanceCoefficient,
        uint24 newVolatilityCoefficient
    ) external onlyOwner {
        if (newMaximumFee >= FEE_DENOMINATOR) revert InvalidPpmValue(newMaximumFee);
        if (newSizeCoefficient > FEE_DENOMINATOR) revert InvalidPpmValue(newSizeCoefficient);
        if (newImbalanceCoefficient > FEE_DENOMINATOR) {
            revert InvalidPpmValue(newImbalanceCoefficient);
        }
        if (newVolatilityCoefficient > FEE_DENOMINATOR) {
            revert InvalidPpmValue(newVolatilityCoefficient);
        }
        if (newMinimumFee > newBaseFee || newBaseFee > newMaximumFee) {
            revert InvalidFeeBounds(newMinimumFee, newBaseFee, newMaximumFee);
        }

        minimumFee = newMinimumFee;
        baseFee = newBaseFee;
        maximumFee = newMaximumFee;
        sizeCoefficient = newSizeCoefficient;
        imbalanceCoefficient = newImbalanceCoefficient;
        volatilityCoefficient = newVolatilityCoefficient;

        emit FeeParametersUpdated(
            newMinimumFee,
            newBaseFee,
            newMaximumFee,
            newSizeCoefficient,
            newImbalanceCoefficient,
            newVolatilityCoefficient
        );
    }

    /// @notice Changes the fraction of assessed fees owned by the protocol.
    /// @param newProtocolFeeShare Protocol share in ppm of the total assessed fee.
    function setProtocolFeeShare(
        uint24 newProtocolFeeShare
    ) external onlyOwner {
        if (newProtocolFeeShare > FEE_DENOMINATOR) {
            revert InvalidPpmValue(newProtocolFeeShare);
        }
        uint24 previousShare = protocolFeeShare;
        protocolFeeShare = newProtocolFeeShare;
        emit ProtocolFeeShareUpdated(previousShare, newProtocolFeeShare);
    }

    /// @notice Configures ratio and volatility inputs for a pool.
    /// @dev Anchors should be the effective reserves observed on the pool's first mint.
    function configurePool(
        address pool,
        address oracle,
        uint128 anchorReserve0,
        uint128 anchorReserve1,
        uint32 volatilityWindow,
        bool oracleEnabled
    ) external onlyOwner {
        if (pool == address(0)) revert ZeroAddress();
        if (anchorReserve0 == 0 || anchorReserve1 == 0) revert InvalidAnchor();
        if (oracleEnabled && (oracle == address(0) || volatilityWindow == 0)) {
            revert ZeroAddress();
        }

        poolConfigurations[pool] = PoolConfiguration({
            oracle: oracle,
            anchorReserve0: anchorReserve0,
            anchorReserve1: anchorReserve1,
            volatilityWindow: volatilityWindow,
            oracleEnabled: oracleEnabled
        });
        emit PoolConfigurationUpdated(
            pool, oracle, anchorReserve0, anchorReserve1, volatilityWindow, oracleEnabled
        );
    }

    /// @inheritdoc IAuralisFeeController
    function quoteFee(
        address pool,
        bool zeroForOne,
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external view override returns (uint24 lpFeePpm, uint24 protocolSharePpm) {
        (,,,, lpFeePpm) = quoteFeeBreakdown(pool, zeroForOne, amountIn, reserveIn, reserveOut);
        protocolSharePpm = protocolFeeShare;
    }

    /// @notice Returns each contribution to a prospective swap fee.
    function quoteFeeBreakdown(
        address pool,
        bool zeroForOne,
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    )
        public
        view
        returns (
            uint24 baseComponent,
            uint24 sizeComponent,
            uint24 imbalanceComponent,
            uint24 volatilityComponent,
            uint24 quotedFee
        )
    {
        baseComponent = baseFee;
        if (
            reserveIn == 0 || reserveOut == 0 || reserveIn > type(uint112).max
                || reserveOut > type(uint112).max || amountIn > type(uint112).max - reserveIn
        ) {
            return (baseComponent, 0, 0, 0, maximumFee);
        }

        uint256 sizePpm = _normalizedFraction(amountIn, reserveIn + amountIn);
        sizeComponent = uint24(FullMath.mulDiv(sizePpm, sizeCoefficient, FEE_DENOMINATOR));

        PoolConfiguration memory configuration = poolConfigurations[pool];
        uint256 imbalancePpm =
            _postTradeImbalance(configuration, zeroForOne, amountIn, reserveIn, reserveOut);
        imbalanceComponent =
            uint24(FullMath.mulDiv(imbalancePpm, imbalanceCoefficient, FEE_DENOMINATOR));

        uint256 volatilityPpm = _readVolatility(configuration);
        volatilityComponent =
            uint24(FullMath.mulDiv(volatilityPpm, volatilityCoefficient, FEE_DENOMINATOR));

        uint256 rawFee =
            uint256(baseComponent) + sizeComponent + imbalanceComponent + volatilityComponent;
        if (rawFee < minimumFee) rawFee = minimumFee;
        if (rawFee > maximumFee) rawFee = maximumFee;
        // The configurable maximum is capped at one million and therefore fits uint24.
        // forge-lint: disable-next-line(unsafe-typecast)
        quotedFee = uint24(rawFee);
    }

    function _postTradeImbalance(
        PoolConfiguration memory configuration,
        bool zeroForOne,
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256) {
        uint256 postReserveIn = reserveIn + amountIn;
        uint256 amountOut = FullMath.mulDiv(reserveOut, amountIn, postReserveIn);
        uint256 postReserveOut = reserveOut - amountOut;
        uint256 postReserve0 = zeroForOne ? postReserveIn : postReserveOut;
        uint256 postReserve1 = zeroForOne ? postReserveOut : postReserveIn;
        uint256 anchorReserve0 = configuration.anchorReserve0;
        uint256 anchorReserve1 = configuration.anchorReserve1;
        if (anchorReserve0 == 0 || anchorReserve1 == 0) {
            anchorReserve0 = zeroForOne ? reserveIn : reserveOut;
            anchorReserve1 = zeroForOne ? reserveOut : reserveIn;
        }

        uint256 left = postReserve0 * anchorReserve1;
        uint256 right = postReserve1 * anchorReserve0;
        uint256 difference = left > right ? left - right : right - left;
        return _normalizedFraction(difference, left + right);
    }

    function _readVolatility(
        PoolConfiguration memory configuration
    ) internal view returns (uint256 sample) {
        if (!configuration.oracleEnabled) return 0;
        try IAuralisVolatilitySource(configuration.oracle)
            .volatility(configuration.volatilityWindow) returns (
            uint256 volatilityPpm
        ) {
            sample = volatilityPpm > MAX_NORMALIZED_VOLATILITY
                ? MAX_NORMALIZED_VOLATILITY
                : volatilityPpm;
        } catch {
            sample = 0;
        }
    }

    function _normalizedFraction(
        uint256 numerator,
        uint256 denominator
    ) internal pure returns (uint256) {
        if (denominator == 0) return FEE_DENOMINATOR;
        return FullMath.mulDiv(numerator, FEE_DENOMINATOR, denominator);
    }
}
