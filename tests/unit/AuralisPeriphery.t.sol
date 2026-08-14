// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { AuralisHealthMonitor } from "../../src/monitoring/AuralisHealthMonitor.sol";
import { AuralisPoolLens } from "../../src/periphery/AuralisPoolLens.sol";
import { BurnQuote, PoolHealth, PoolSnapshot } from "../../src/types/AuralisTypes.sol";
import { PoolTestBase } from "../helpers/PoolTestBase.sol";

contract AuralisPeripheryTest is PoolTestBase {
    AuralisPoolLens internal lens;
    AuralisHealthMonitor internal monitor;

    function setUp() public override {
        super.setUp();
        lens = new AuralisPoolLens(address(factory));
        monitor = new AuralisHealthMonitor(address(factory), 1 days);
    }

    function test_SnapshotReconcilesPoolAccounting() public {
        _initializePool();
        _swap(TRADER, token0, DEFAULT_SWAP_INPUT);

        PoolSnapshot memory state = lens.snapshot(address(pool));

        assertEq(state.pool, address(pool));
        assertEq(state.token0, address(token0));
        assertEq(state.token1, address(token1));
        assertEq(
            state.grossReserve0, state.activeReserve0 + state.pendingLPFee0 + state.protocolFee0
        );
        assertEq(
            state.grossReserve1, state.activeReserve1 + state.pendingLPFee1 + state.protocolFee1
        );
        assertFalse(state.paused);
    }

    function test_PartialRedemptionQuoteSeparatesSettlementFields() public {
        uint256 minted = _initializePool();

        BurnQuote memory quote = lens.quoteBurn(address(pool), ALICE, minted / 4);

        assertEq(quote.amount0, quote.principal0);
        assertEq(quote.amount1, quote.principal1);
        assertEq(quote.realizedFee0, 0);
        assertEq(quote.realizedFee1, 0);
        assertFalse(quote.closesPosition);
    }

    function test_ClosingRedemptionQuoteIncludesCheckpointedFees() public {
        uint256 minted = _initializePool();
        _swap(TRADER, token0, DEFAULT_SWAP_INPUT);

        BurnQuote memory quote = lens.quoteBurn(address(pool), ALICE, minted);

        assertTrue(quote.closesPosition);
        assertEq(quote.amount0, quote.principal0 + quote.realizedFee0);
        assertEq(quote.amount1, quote.principal1 + quote.realizedFee1);
        assertGt(quote.realizedFee0, 0);
    }

    function test_HealthyPoolProducesNoOperationalFlags() public {
        _initializePool();

        PoolHealth memory report = monitor.inspect(address(pool));

        assertTrue(report.healthy);
        assertEq(report.flags, 0);
        assertEq(report.physicalBalance0, report.grossReserve0);
        assertEq(report.physicalBalance1, report.grossReserve1);
    }

    function test_PausedPoolIsReported() public {
        _initializePool();
        vm.prank(GUARDIAN);
        factory.setPoolPaused(address(pool), true);

        PoolHealth memory report = monitor.inspect(address(pool));

        assertFalse(report.healthy);
        assertTrue((report.flags & monitor.FLAG_PAUSED()) != 0);
    }

    function test_UnaccountedBalanceIsReported() public {
        _initializePool();
        vm.prank(ALICE);
        assertTrue(token0.transfer(address(pool), 1 ether));

        PoolHealth memory report = monitor.inspect(address(pool));

        assertFalse(report.healthy);
        assertTrue((report.flags & monitor.FLAG_ACCOUNTING_MISMATCH()) != 0);
    }

    function test_StaleOracleIsReported() public {
        _initializePool();
        vm.warp(block.timestamp + 1 days + 1);

        PoolHealth memory report = monitor.inspect(address(pool));

        assertFalse(report.healthy);
        assertGt(report.oracleAge, monitor.maximumOracleAge());
        assertTrue((report.flags & monitor.FLAG_ORACLE_STALE()) != 0);
    }

    function test_BatchInspectionPreservesInputOrder() public {
        _initializePool();
        address[] memory pools = new address[](1);
        pools[0] = address(pool);

        PoolHealth[] memory reports = monitor.inspectMany(pools);

        assertEq(reports.length, 1);
        assertEq(reports[0].pool, address(pool));
    }
}
