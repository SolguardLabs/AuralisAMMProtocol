// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { AuralisLPToken } from "../../src/tokens/AuralisLPToken.sol";
import {
    AuralisAmount0BelowMinimum,
    AuralisDeadlineExpired,
    AuralisImbalanceExceeded,
    AuralisInsufficientLiquidity,
    AuralisInvalidToken,
    AuralisOutputBelowMinimum,
    AuralisPoolNotInitialized,
    AuralisPoolPaused,
    AuralisUnsupportedToken,
    AuralisZeroAddress,
    AuralisZeroAmount
} from "../../src/types/AuralisErrors.sol";
import { PoolTestBase } from "../helpers/PoolTestBase.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

contract AuralisPoolTest is PoolTestBase {
    function test_InitialLiquidityEstablishesReservesAndLockedSupply() public {
        uint256 liquidity = _initializePool();
        (uint256 gross0, uint256 gross1) = _grossReserves();

        assertEq(gross0, INITIAL_LIQUIDITY);
        assertEq(gross1, INITIAL_LIQUIDITY);
        assertEq(liquidity, INITIAL_LIQUIDITY - 1000);
        assertEq(pool.balanceOf(ALICE), liquidity);
        assertEq(pool.totalSupply(), INITIAL_LIQUIDITY);
        assertEq(pool.feeBearingSupply(), liquidity);
        _assertAccountingReconciles();
    }

    function test_SecondContributionUsesCurrentReserveRatio() public {
        _initializePool();

        (uint256 expected0, uint256 expected1, uint256 expectedLiquidity) =
            pool.previewMint(100_000 ether, 125_000 ether);
        vm.prank(BOB);
        (uint256 amount0, uint256 amount1, uint256 liquidity) =
            pool.mint(BOB, 100_000 ether, 125_000 ether, expected0, expected1, block.timestamp);

        assertEq(amount0, 100_000 ether);
        assertEq(amount1, 100_000 ether);
        assertEq(amount0, expected0);
        assertEq(amount1, expected1);
        assertEq(liquidity, expectedLiquidity);
        assertEq(pool.balanceOf(BOB), expectedLiquidity);
        _assertAccountingReconciles();
    }

    function test_PartialRedemptionReturnsProportionalAssets() public {
        uint256 minted = _initializePool();
        uint256 liquidity = minted / 4;
        (uint256 expected0, uint256 expected1) = pool.previewBurn(ALICE, liquidity);
        uint256 balance0Before = token0.balanceOf(ALICE);
        uint256 balance1Before = token1.balanceOf(ALICE);

        vm.prank(ALICE);
        (uint256 amount0, uint256 amount1) =
            pool.burn(ALICE, ALICE, liquidity, expected0, expected1, block.timestamp);

        assertEq(amount0, expected0);
        assertEq(amount1, expected1);
        assertEq(token0.balanceOf(ALICE) - balance0Before, amount0);
        assertEq(token1.balanceOf(ALICE) - balance1Before, amount1);
        assertEq(pool.balanceOf(ALICE), minted - liquidity);
        _assertAccountingReconciles();
    }

    function test_ApprovedOperatorCanRedeemOwnerShares() public {
        uint256 minted = _initializePool();
        uint256 liquidity = minted / 10;

        vm.prank(ALICE);
        pool.approve(BOB, liquidity);
        vm.prank(BOB);
        pool.burn(ALICE, BOB, liquidity, 0, 0, block.timestamp);

        assertEq(pool.allowance(ALICE, BOB), 0);
        assertEq(pool.balanceOf(ALICE), minted - liquidity);
        assertGt(token0.balanceOf(BOB), 5_000_000 ether);
        assertGt(token1.balanceOf(BOB), 5_000_000 ether);
    }

    function test_SwapMatchesQuoteAndPreservesCurveInvariant() public {
        _initializePool();
        (uint112 active0Before, uint112 active1Before) = pool.activeReserves();
        (uint256 quotedOut,,) = pool.quoteExactInput(address(token0), DEFAULT_SWAP_INPUT);
        uint256 recipientBefore = token1.balanceOf(TRADER);

        uint256 amountOut = _swap(TRADER, token0, DEFAULT_SWAP_INPUT);
        (uint112 active0After, uint112 active1After) = pool.activeReserves();

        assertEq(amountOut, quotedOut);
        assertEq(token1.balanceOf(TRADER) - recipientBefore, amountOut);
        assertGe(
            uint256(active0After) * uint256(active1After),
            uint256(active0Before) * uint256(active1Before)
        );
        _assertAccountingReconciles();
    }

    function test_SwapAccumulatesSeparatedFeeBalances() public {
        _initializePool();
        (, uint256 quotedLPFee, uint256 quotedProtocolFee) =
            pool.quoteExactInput(address(token0), DEFAULT_SWAP_INPUT);

        _swap(TRADER, token0, DEFAULT_SWAP_INPUT);

        (uint128 pending0, uint128 pending1) = pool.pendingLPFees();
        (uint128 protocol0, uint128 protocol1) = pool.protocolFees();
        (uint256 growth0, uint256 growth1) = pool.feeGrowthGlobalX128();
        assertEq(pending0, quotedLPFee);
        assertEq(pending1, 0);
        assertEq(protocol0, quotedProtocolFee);
        assertEq(protocol1, 0);
        assertGt(growth0, 0);
        assertEq(growth1, 0);
        _assertAccountingReconciles();
    }

    function test_LiquidityProviderCanClaimAccruedFees() public {
        _initializePool();
        _swap(TRADER, token0, DEFAULT_SWAP_INPUT);
        (uint256 accrued0, uint256 accrued1) = pool.accruedFees(ALICE);
        (uint128 pendingBefore,) = pool.pendingLPFees();
        uint256 recipientBefore = token0.balanceOf(BOB);

        vm.prank(ALICE);
        (uint256 claimed0, uint256 claimed1) = pool.claimFees(BOB);

        assertEq(claimed0, accrued0);
        assertEq(claimed1, accrued1);
        assertEq(token0.balanceOf(BOB) - recipientBefore, claimed0);
        (uint128 pendingAfter,) = pool.pendingLPFees();
        assertEq(uint256(pendingAfter) + claimed0, pendingBefore);
        (uint256 remaining0, uint256 remaining1) = pool.accruedFees(ALICE);
        assertEq(remaining0, 0);
        assertEq(remaining1, 0);
        (uint256 checkpoint0, uint256 checkpoint1) = pool.feeGrowthCheckpoint(ALICE);
        (uint256 global0, uint256 global1) = pool.feeGrowthGlobalX128();
        assertEq(checkpoint0, global0);
        assertEq(checkpoint1, global1);
        _assertAccountingReconciles();
    }

    function test_ShareTransferCheckpointsBothAccounts() public {
        uint256 minted = _initializePool();
        _swap(TRADER, token0, DEFAULT_SWAP_INPUT);
        (uint256 aliceBefore,) = pool.accruedFees(ALICE);

        vm.prank(ALICE);
        assertTrue(pool.transfer(BOB, minted / 2));
        (uint256 bobBefore,) = pool.accruedFees(BOB);
        _swap(TRADER, token0, DEFAULT_SWAP_INPUT);
        (uint256 aliceAfter,) = pool.accruedFees(ALICE);
        (uint256 bobAfter,) = pool.accruedFees(BOB);

        assertEq(bobBefore, 0);
        assertGt(aliceAfter, aliceBefore);
        assertGt(bobAfter, 0);
        assertApproxEqAbs(aliceAfter - aliceBefore, bobAfter, 2);
    }

    function test_ClosingPositionIncludesAccruedFees() public {
        uint256 minted = _initializePool();
        _swap(TRADER, token0, DEFAULT_SWAP_INPUT);
        (uint256 accrued0,) = pool.accruedFees(ALICE);
        (uint256 preview0, uint256 preview1) = pool.previewBurn(ALICE, minted);
        uint256 balance0Before = token0.balanceOf(ALICE);

        vm.prank(ALICE);
        (uint256 amount0, uint256 amount1) =
            pool.burn(ALICE, ALICE, minted, preview0, preview1, block.timestamp);

        assertEq(amount0, preview0);
        assertEq(amount1, preview1);
        assertEq(token0.balanceOf(ALICE) - balance0Before, amount0);
        assertGt(accrued0, 0);
        assertEq(pool.balanceOf(ALICE), 0);
        _assertAccountingReconciles();
    }

    function test_ProtocolFeesAreSentToConfiguredRecipient() public {
        _initializePool();
        _swap(TRADER, token0, DEFAULT_SWAP_INPUT);
        (uint128 protocol0Before, uint128 protocol1Before) = pool.protocolFees();
        uint256 recipient0Before = token0.balanceOf(PROTOCOL_RECIPIENT);

        (uint256 collected0, uint256 collected1) = pool.collectProtocolFees();

        assertEq(collected0, protocol0Before);
        assertEq(collected1, protocol1Before);
        assertEq(token0.balanceOf(PROTOCOL_RECIPIENT) - recipient0Before, collected0);
        (uint128 remaining0, uint128 remaining1) = pool.protocolFees();
        assertEq(remaining0, 0);
        assertEq(remaining1, 0);
        _assertAccountingReconciles();
    }

    function test_SkimReturnsOnlyUnaccountedTokens() public {
        _initializePool();
        uint256 donation = 500 ether;
        vm.prank(ALICE);
        assertTrue(token0.transfer(address(pool), donation));
        uint256 recipientBefore = token0.balanceOf(BOB);

        pool.skim(BOB);

        assertEq(token0.balanceOf(BOB) - recipientBefore, donation);
        _assertAccountingReconciles();
    }

    function test_SyncIncludesBalancedDonationsInActiveReserves() public {
        _initializePool();
        (uint112 active0Before, uint112 active1Before) = pool.activeReserves();
        uint256 donation = 500 ether;
        vm.startPrank(ALICE);
        assertTrue(token0.transfer(address(pool), donation));
        assertTrue(token1.transfer(address(pool), donation));
        vm.stopPrank();

        pool.sync();
        (uint112 active0After, uint112 active1After) = pool.activeReserves();

        assertEq(active0After, uint256(active0Before) + donation);
        assertEq(active1After, uint256(active1Before) + donation);
        _assertAccountingReconciles();
    }

    function test_RevertWhenSwapOutputIsBelowLimit() public {
        _initializePool();
        (uint256 quotedOut,,) = pool.quoteExactInput(address(token0), DEFAULT_SWAP_INPUT);

        vm.prank(TRADER);
        vm.expectRevert(
            abi.encodeWithSelector(AuralisOutputBelowMinimum.selector, quotedOut + 1, quotedOut)
        );
        pool.swapExactInput(
            address(token0), DEFAULT_SWAP_INPUT, quotedOut + 1, TRADER, block.timestamp
        );
    }

    function test_RevertWhenMintMinimumIsNotMet() public {
        _initializePool();
        (uint256 amount0,,) = pool.previewMint(100_000 ether, 100_000 ether);

        vm.prank(BOB);
        vm.expectRevert(
            abi.encodeWithSelector(AuralisAmount0BelowMinimum.selector, amount0 + 1, amount0)
        );
        pool.mint(BOB, 100_000 ether, 100_000 ether, amount0 + 1, 0, block.timestamp);
    }

    function test_RevertWhenDeadlineHasExpired() public {
        _initializePool();
        uint256 expired = block.timestamp - 1;

        vm.prank(TRADER);
        vm.expectRevert(
            abi.encodeWithSelector(AuralisDeadlineExpired.selector, expired, block.timestamp)
        );
        pool.swapExactInput(address(token0), 1 ether, 0, TRADER, expired);
    }

    function test_RevertWhenTokenIsNotInPool() public {
        _initializePool();
        MockERC20 unknown = new MockERC20("Unknown", "UNKNOWN", 18);

        vm.expectRevert(abi.encodeWithSelector(AuralisInvalidToken.selector, address(unknown)));
        pool.quoteExactInput(address(unknown), 1 ether);
    }

    function test_RevertWhenSwapIsQuotedBeforeInitialization() public {
        vm.expectRevert(AuralisPoolNotInitialized.selector);
        pool.quoteExactInput(address(token0), 1 ether);
    }

    function test_RevertWhenSwapAmountIsZero() public {
        _initializePool();

        vm.expectRevert(AuralisZeroAmount.selector);
        pool.quoteExactInput(address(token0), 0);
    }

    function test_RevertWhenBurnExceedsOwnerBalance() public {
        uint256 minted = _initializePool();

        vm.prank(ALICE);
        vm.expectRevert(AuralisInsufficientLiquidity.selector);
        pool.burn(ALICE, ALICE, minted + 1, 0, 0, block.timestamp);
    }

    function test_RevertWhenRecipientIsZeroAddress() public {
        _initializePool();

        vm.prank(TRADER);
        vm.expectRevert(AuralisZeroAddress.selector);
        pool.swapExactInput(address(token0), 1 ether, 0, address(0), block.timestamp);
    }

    function test_RevertWhenPoolIsPaused() public {
        _initializePool();
        vm.prank(GUARDIAN);
        factory.setPoolPaused(address(pool), true);

        vm.prank(TRADER);
        vm.expectRevert(AuralisPoolPaused.selector);
        pool.swapExactInput(address(token0), 1 ether, 0, TRADER, block.timestamp);
    }

    function test_RevertWhenInputTokenChargesTransferFee() public {
        _initializePool();
        token0.setTransferFee(10_000, address(0xCAFE));
        uint256 amountIn = 100 ether;
        uint256 received = 99 ether;

        vm.prank(TRADER);
        vm.expectRevert(
            abi.encodeWithSelector(
                AuralisUnsupportedToken.selector, address(token0), amountIn, received
            )
        );
        pool.swapExactInput(address(token0), amountIn, 0, TRADER, block.timestamp);
    }

    function test_RevertWhenProjectedCompositionExceedsLimit() public {
        _initializePool();

        vm.expectRevert(
            abi.encodeWithSelector(
                AuralisImbalanceExceeded.selector, uint256(381_766), uint256(250_000)
            )
        );
        pool.quoteExactInput(address(token0), 500_000 ether);
    }
}
