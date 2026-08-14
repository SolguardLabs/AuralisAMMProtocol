// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IAuralisFactory } from "../interfaces/IAuralisFactory.sol";
import { IAuralisOracle } from "../interfaces/IAuralisOracle.sol";
import { IAuralisPool } from "../interfaces/IAuralisPool.sol";
import { IERC20Minimal } from "../interfaces/IERC20Minimal.sol";
import { AuralisInvalidConfiguration, AuralisUnknownPool } from "../types/AuralisErrors.sol";
import { PoolHealth, RiskStatus } from "../types/AuralisTypes.sol";

interface IAuralisPoolRiskSource {
    function imbalanceGuard() external view returns (address guard);
}

interface IAuralisRiskMonitor {
    function evaluate(
        address pool,
        uint256 reserve0,
        uint256 reserve1
    ) external view returns (RiskStatus memory status);
}

/// @title Auralis health monitor
/// @notice Produces deterministic operational signals from pool, reserve and oracle state.
contract AuralisHealthMonitor {
    uint256 public constant FLAG_PAUSED = 1 << 0;
    uint256 public constant FLAG_ACCOUNTING_MISMATCH = 1 << 1;
    uint256 public constant FLAG_RESERVE_FLOOR = 1 << 2;
    uint256 public constant FLAG_IMBALANCE = 1 << 3;
    uint256 public constant FLAG_ORACLE_STALE = 1 << 4;
    uint256 public constant MAX_BATCH_SIZE = 64;

    address public immutable factory;
    uint256 public immutable maximumOracleAge;

    constructor(
        address factory_,
        uint256 maximumOracleAge_
    ) {
        if (factory_ == address(0) || factory_.code.length == 0 || maximumOracleAge_ == 0) {
            revert AuralisInvalidConfiguration();
        }
        factory = factory_;
        maximumOracleAge = maximumOracleAge_;
    }

    /// @notice Inspects one canonical pool and returns a bitmapped health assessment.
    function inspect(
        address poolAddress
    ) public view returns (PoolHealth memory report) {
        IAuralisPool pool = _canonicalPool(poolAddress);
        report.pool = poolAddress;
        {
            (uint112 gross0, uint112 gross1,) = pool.getReserves();
            (uint112 active0, uint112 active1) = pool.activeReserves();
            report.grossReserve0 = gross0;
            report.grossReserve1 = gross1;
            report.activeReserve0 = active0;
            report.activeReserve1 = active1;
        }
        {
            (uint128 pending0, uint128 pending1) = pool.pendingLPFees();
            (uint128 protocol0, uint128 protocol1) = pool.protocolFees();
            report.obligations0 = uint256(pending0) + protocol0;
            report.obligations1 = uint256(pending1) + protocol1;
        }
        report.physicalBalance0 = IERC20Minimal(pool.token0()).balanceOf(poolAddress);
        report.physicalBalance1 = IERC20Minimal(pool.token1()).balanceOf(poolAddress);

        if (pool.paused()) report.flags |= FLAG_PAUSED;
        if (
            report.physicalBalance0 != report.grossReserve0
                || report.physicalBalance1 != report.grossReserve1
                || report.activeReserve0 + report.obligations0 != report.grossReserve0
                || report.activeReserve1 + report.obligations1 != report.grossReserve1
        ) report.flags |= FLAG_ACCOUNTING_MISMATCH;

        uint256 minimum = pool.minimumReserve();
        if (report.activeReserve0 < minimum || report.activeReserve1 < minimum) {
            report.flags |= FLAG_RESERVE_FLOOR;
        }

        {
            address guard = IAuralisPoolRiskSource(poolAddress).imbalanceGuard();
            RiskStatus memory risk = IAuralisRiskMonitor(guard)
                .evaluate(poolAddress, report.activeReserve0, report.activeReserve1);
            report.imbalancePpm = risk.imbalancePpm;
            if (!risk.accepted) report.flags |= FLAG_IMBALANCE;
        }

        report.oracleAge = _oracleAge(pool.oracle());
        if (report.oracleAge > maximumOracleAge) report.flags |= FLAG_ORACLE_STALE;
        report.healthy = report.flags == 0;
    }

    /// @notice Inspects a bounded list of canonical pools in one call.
    function inspectMany(
        address[] calldata pools
    ) external view returns (PoolHealth[] memory reports) {
        uint256 length = pools.length;
        if (length == 0 || length > MAX_BATCH_SIZE) revert AuralisInvalidConfiguration();
        reports = new PoolHealth[](length);
        for (uint256 i; i < length; ++i) {
            reports[i] = inspect(pools[i]);
        }
    }

    function _oracleAge(
        address oracleAddress
    ) internal view returns (uint256 age) {
        if (oracleAddress == address(0) || oracleAddress.code.length == 0) {
            return type(uint256).max;
        }
        IAuralisOracle oracle = IAuralisOracle(oracleAddress);
        uint16 count = oracle.cardinality();
        if (count == 0) return type(uint256).max;

        uint16 next = oracle.observationIndex();
        uint256 latestIndex = next == 0 ? uint256(count) - 1 : uint256(next) - 1;
        (uint32 timestamp,,) = oracle.observations(latestIndex);
        // The comparison protects monitoring arithmetic against malformed oracle data.
        // forge-lint: disable-next-line(block-timestamp)
        if (timestamp > block.timestamp) return type(uint256).max;
        age = block.timestamp - timestamp;
    }

    function _canonicalPool(
        address poolAddress
    ) internal view returns (IAuralisPool pool) {
        if (poolAddress == address(0) || poolAddress.code.length == 0) {
            revert AuralisUnknownPool(poolAddress);
        }
        pool = IAuralisPool(poolAddress);
        if (
            pool.factory() != factory
                || IAuralisFactory(factory).getPool(pool.token0(), pool.token1()) != poolAddress
        ) revert AuralisUnknownPool(poolAddress);
    }
}
