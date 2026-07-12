// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { DynamicFeeController } from "../../src/fees/DynamicFeeController.sol";
import { Ownable2Step } from "../../src/utils/Ownable2Step.sol";
import { TestBase } from "../helpers/TestBase.sol";
import { MockVolatilityOracle } from "../mocks/MockVolatilityOracle.sol";

contract DynamicFeeControllerTest is TestBase {
    DynamicFeeController internal controller;
    MockVolatilityOracle internal volatilityOracle;

    address internal constant POOL = address(0xA11CE);
    address internal constant OTHER = address(0xB0B);

    function setUp() public {
        controller = new DynamicFeeController(address(this));
        volatilityOracle = new MockVolatilityOracle();
    }

    function test_DefaultConfigurationIsBounded() public view {
        assertEq(controller.owner(), address(this));
        assertEq(controller.minimumFee(), 500);
        assertEq(controller.baseFee(), 3000);
        assertEq(controller.maximumFee(), 30_000);
        assertEq(controller.protocolFeeShare(), 100_000);
        assertEq(controller.FEE_DENOMINATOR(), 1_000_000);
    }

    function test_TradeSizeRaisesQuotedFee() public view {
        (uint24 smallFee,) = controller.quoteFee(POOL, true, 1e18, 1000e18, 1000e18);
        (uint24 largeFee,) = controller.quoteFee(POOL, true, 100e18, 1000e18, 1000e18);

        assertGt(largeFee, smallFee);
        assertGe(smallFee, controller.minimumFee());
        assertLe(largeFee, controller.maximumFee());
    }

    function test_VolatilityContributesToQuote() public {
        controller.configurePool(
            POOL, address(volatilityOracle), uint128(1000e18), uint128(1000e18), 1 hours, true
        );

        volatilityOracle.setSample(0);
        (uint24 calmFee,) = controller.quoteFee(POOL, true, 10e18, 1000e18, 1000e18);
        volatilityOracle.setSample(400_000);
        (uint24 volatileFee,) = controller.quoteFee(POOL, true, 10e18, 1000e18, 1000e18);

        assertGt(volatileFee, calmFee);
    }

    function test_UnavailableVolatilitySourceIsIgnored() public {
        controller.configurePool(
            POOL, address(volatilityOracle), uint128(1000e18), uint128(1000e18), 1 hours, true
        );
        volatilityOracle.setShouldRevert(true);

        (,,, uint24 volatilityComponent, uint24 quotedFee) =
            controller.quoteFeeBreakdown(POOL, true, 10e18, 1000e18, 1000e18);

        assertEq(volatilityComponent, 0);
        assertGe(quotedFee, controller.baseFee());
    }

    function test_QuoteIsCappedAtConfiguredMaximum() public {
        controller.setFeeParameters(500, 3000, 10_000, 1_000_000, 1_000_000, 1_000_000);

        (uint24 quotedFee,) = controller.quoteFee(POOL, true, 900e18, 1000e18, 1000e18);

        assertEq(quotedFee, 10_000);
    }

    function test_ProtocolShareCanBeUpdated() public {
        controller.setProtocolFeeShare(250_000);

        (, uint24 protocolShare) = controller.quoteFee(POOL, true, 1e18, 100e18, 100e18);
        assertEq(protocolShare, 250_000);
    }

    function test_OwnershipTransferRequiresNomineeAcceptance() public {
        controller.transferOwnership(OTHER);
        assertEq(controller.owner(), address(this));
        assertEq(controller.pendingOwner(), OTHER);

        vm.prank(OTHER);
        controller.acceptOwnership();

        assertEq(controller.owner(), OTHER);
        assertEq(controller.pendingOwner(), address(0));
    }

    function test_RevertWhenNonOwnerUpdatesParameters() public {
        vm.prank(OTHER);
        vm.expectRevert(abi.encodeWithSelector(Ownable2Step.Unauthorized.selector, OTHER));
        controller.setFeeParameters(500, 3000, 30_000, 20_000, 40_000, 25_000);
    }

    function test_RevertWhenProtocolShareExceedsDenominator() public {
        vm.expectRevert(
            abi.encodeWithSelector(DynamicFeeController.InvalidPpmValue.selector, 1_000_001)
        );
        controller.setProtocolFeeShare(1_000_001);
    }

    function test_RevertWhenMaximumFeeReachesDenominator() public {
        vm.expectRevert(
            abi.encodeWithSelector(DynamicFeeController.InvalidPpmValue.selector, 1_000_000)
        );
        controller.setFeeParameters(500, 3000, 1_000_000, 0, 0, 0);
    }

    function test_RevertWhenFeeBoundsAreInconsistent() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DynamicFeeController.InvalidFeeBounds.selector,
                uint24(4000),
                uint24(3000),
                uint24(5000)
            )
        );
        controller.setFeeParameters(4000, 3000, 5000, 0, 0, 0);
    }

    function test_RevertWhenEnabledOracleConfigurationIsIncomplete() public {
        vm.expectRevert(DynamicFeeController.ZeroAddress.selector);
        controller.configurePool(POOL, address(0), 1, 1, 1 hours, true);
    }
}
