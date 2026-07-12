// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ImbalanceGuard } from "../../src/risk/ImbalanceGuard.sol";
import {
    AuralisImbalanceExceeded,
    AuralisInvalidConfiguration,
    AuralisReserveBelowMinimum,
    AuralisUnauthorized
} from "../../src/types/AuralisErrors.sol";
import { PoolRiskConfig, RiskStatus } from "../../src/types/AuralisTypes.sol";
import { TestBase } from "../helpers/TestBase.sol";

contract ImbalanceGuardTest is TestBase {
    ImbalanceGuard internal guard;

    address internal constant POOL = address(0xA11CE);
    address internal constant OTHER = address(0xB0B);

    function setUp() public {
        vm.warp(1000);
        guard = new ImbalanceGuard(address(this));
    }

    function test_DefaultPolicyIsAvailableToEveryPool() public view {
        PoolRiskConfig memory configuration = guard.riskConfig(POOL);

        assertEq(configuration.maximumImbalancePpm, 250_000);
        assertEq(configuration.minimumActiveReserve, 1000);
    }

    function test_InitializationStoresImmutableRatioAnchor() public {
        guard.initializePool(POOL, 10_000, 20_000);
        ImbalanceGuard.PoolAnchor memory anchor = guard.poolAnchor(POOL);

        assertEq(anchor.reserve0, 10_000);
        assertEq(anchor.reserve1, 20_000);
        assertEq(anchor.initializedAt, 1000);
        assertEq(guard.anchorRatioX128(POOL), uint256(2) << 128);
    }

    function test_ProportionalReservesHaveNoMeasuredImbalance() public {
        guard.initializePool(POOL, 10_000, 20_000);

        uint256 imbalancePpm = guard.checkVirtualReserves(POOL, 15_000, 30_000);
        assertEq(imbalancePpm, 0);
    }

    function test_EvaluateReportsAcceptedAndRejectedStates() public {
        guard.initializePool(POOL, 10_000, 10_000);

        RiskStatus memory accepted = guard.evaluate(POOL, 11_000, 11_000);
        RiskStatus memory rejected = guard.evaluate(POOL, 20_000, 10_000);

        assertTrue(accepted.initialized);
        assertTrue(accepted.accepted);
        assertFalse(rejected.accepted);
        assertGt(rejected.imbalancePpm, rejected.maximumImbalancePpm);
    }

    function test_CustomPolicyCanBeSetAndCleared() public {
        PoolRiskConfig memory custom =
            PoolRiskConfig({ maximumImbalancePpm: 100_000, minimumActiveReserve: 5000 });
        guard.setPoolRiskConfig(POOL, custom);

        PoolRiskConfig memory configured = guard.riskConfig(POOL);
        assertEq(configured.maximumImbalancePpm, 100_000);
        assertEq(configured.minimumActiveReserve, 5000);

        guard.clearPoolRiskConfig(POOL);
        PoolRiskConfig memory restored = guard.riskConfig(POOL);
        assertEq(restored.maximumImbalancePpm, 250_000);
        assertEq(restored.minimumActiveReserve, 1000);
    }

    function test_RevertWhenProjectedRatioLeavesRiskBand() public {
        guard.initializePool(POOL, 10_000, 20_000);

        vm.expectRevert(
            abi.encodeWithSelector(
                AuralisImbalanceExceeded.selector, uint256(333_333), uint256(250_000)
            )
        );
        guard.checkVirtualReserves(POOL, 20_000, 20_000);
    }

    function test_RevertWhenReserveFallsBelowMinimum() public {
        guard.initializePool(POOL, 10_000, 10_000);

        vm.expectRevert(
            abi.encodeWithSelector(AuralisReserveBelowMinimum.selector, uint256(999), uint256(1000))
        );
        guard.checkVirtualReserves(POOL, 999, 10_000);
    }

    function test_RevertWhenUntrustedAccountInitializesPool() public {
        vm.prank(OTHER);
        vm.expectRevert(abi.encodeWithSelector(AuralisUnauthorized.selector, OTHER));
        guard.initializePool(POOL, 10_000, 10_000);
    }

    function test_RevertWhenPoolIsInitializedTwice() public {
        guard.initializePool(POOL, 10_000, 10_000);

        vm.expectRevert(AuralisInvalidConfiguration.selector);
        guard.initializePool(POOL, 10_000, 10_000);
    }

    function test_RevertWhenRiskConfigurationIsInvalid() public {
        PoolRiskConfig memory invalid =
            PoolRiskConfig({ maximumImbalancePpm: 0, minimumActiveReserve: 1000 });

        vm.expectRevert(AuralisInvalidConfiguration.selector);
        guard.setDefaultRiskConfig(invalid);
    }
}
