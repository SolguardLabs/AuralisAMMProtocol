// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { AuralisMath } from "../../src/libraries/AuralisMath.sol";
import { ReserveMath } from "../../src/libraries/ReserveMath.sol";
import { TestBase } from "../helpers/TestBase.sol";

contract AuralisMathFuzzTest is TestBase {
    function testFuzz_SquareRootIsFloored(
        uint256 value
    ) public pure {
        value = value % type(uint128).max;
        uint256 root = AuralisMath.sqrt(value);

        assertLe(root * root, value);
        assertGt((root + 1) * (root + 1), value);
    }

    function testFuzz_InitialLiquidityMatchesGeometricMean(
        uint256 amount0,
        uint256 amount1
    ) public pure {
        amount0 = 1_000_001 + (amount0 % 1e24);
        amount1 = 1_000_001 + (amount1 % 1e24);

        uint256 liquidity = AuralisMath.initialLiquidity(amount0, amount1);
        assertEq(liquidity, AuralisMath.sqrt(amount0 * amount1) - 1000);
    }

    function testFuzz_FeeSplitConservesGrossInput(
        uint256 amountIn,
        uint24 feePpm,
        uint24 protocolSharePpm
    ) public pure {
        amountIn = 1 + (amountIn % 1e30);
        feePpm = uint24(uint256(feePpm) % 999_999);
        protocolSharePpm = uint24(uint256(protocolSharePpm) % 1_000_001);

        (uint256 netAmountIn, uint256 lpFee, uint256 protocolFee) =
            AuralisMath.splitFee(amountIn, feePpm, protocolSharePpm);

        assertEq(netAmountIn + lpFee + protocolFee, amountIn);
        assertLe(protocolFee, lpFee + protocolFee);
    }

    function testFuzz_ExactInputDoesNotDecreaseConstantProduct(
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 amountIn
    ) public pure {
        reserveIn = 1e18 + (reserveIn % 1e24);
        reserveOut = 1e18 + (reserveOut % 1e24);
        amountIn = (reserveIn / 1_000_000) + 1 + (amountIn % reserveIn);

        uint256 amountOut = ReserveMath.amountOut(amountIn, reserveIn, reserveOut);
        uint256 invariantBefore = ReserveMath.invariant(reserveIn, reserveOut);
        uint256 invariantAfter = ReserveMath.invariant(reserveIn + amountIn, reserveOut - amountOut);

        assertGe(invariantAfter, invariantBefore);
        assertLt(amountOut, reserveOut);
    }

    function testFuzz_ExactOutputInputIsSufficient(
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 requestedOut
    ) public pure {
        reserveIn = 1e6 + (reserveIn % 1e24);
        reserveOut = 1e6 + (reserveOut % 1e24);
        requestedOut = 1 + (requestedOut % (reserveOut - 1));

        uint256 requiredInput = ReserveMath.netAmountIn(requestedOut, reserveIn, reserveOut);
        uint256 resultingOut = ReserveMath.amountOut(requiredInput, reserveIn, reserveOut);

        assertGe(resultingOut, requestedOut);
    }

    function testFuzz_LiquidityAmountsRemainProportional(
        uint256 reserve0,
        uint256 reserve1,
        uint256 supply,
        uint256 liquidity
    ) public pure {
        reserve0 = 1e12 + (reserve0 % 1e24);
        reserve1 = 1e12 + (reserve1 % 1e24);
        uint256 smallestReserve = AuralisMath.min(reserve0, reserve1);
        supply = 1 + (supply % smallestReserve);
        liquidity = 1 + (liquidity % supply);

        (uint256 amount0, uint256 amount1) =
            ReserveMath.withdrawalAmounts(liquidity, supply, reserve0, reserve1);

        assertLe(amount0, reserve0);
        assertLe(amount1, reserve1);
        assertApproxEqAbs(amount0 * reserve1, amount1 * reserve0, reserve0 + reserve1);
    }

    function testFuzz_ImbalanceIsSymmetricAndBounded(
        uint256 reserve0,
        uint256 reserve1
    ) public pure {
        reserve0 %= 1e30;
        reserve1 %= 1e30;

        uint256 forward = AuralisMath.imbalancePpm(reserve0, reserve1);
        uint256 reverse = AuralisMath.imbalancePpm(reserve1, reserve0);

        assertEq(forward, reverse);
        assertLe(forward, 1_000_000);
    }
}
