// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { FullMath } from "./FullMath.sol";

/// @title General Auralis arithmetic
/// @notice Shared liquidity, fee, ratio and fixed-width conversion helpers.
library AuralisMath {
    uint256 internal constant FEE_DENOMINATOR = 1_000_000;
    uint256 internal constant BPS_DENOMINATOR = 10_000;
    uint256 internal constant MINIMUM_LIQUIDITY = 1000;

    error ZeroAmount();
    error ZeroReserve();
    error InvalidFee();
    error InvalidProtocolShare();
    error InsufficientInitialLiquidity();
    error ArithmeticOverflow();

    /// @notice Returns the smaller of `a` and `b`.
    function min(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /// @notice Returns the larger of `a` and `b`.
    function max(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    /// @notice Returns the absolute difference between two unsigned values.
    function absDiff(
        uint256 a,
        uint256 b
    ) internal pure returns (uint256) {
        return a >= b ? a - b : b - a;
    }

    /// @notice Restricts `value` to the inclusive interval [`lower`, `upper`].
    function clamp(
        uint256 value,
        uint256 lower,
        uint256 upper
    ) internal pure returns (uint256) {
        if (lower > upper) revert ArithmeticOverflow();
        return value < lower ? lower : value > upper ? upper : value;
    }

    /// @notice Returns floor(sqrt(value)).
    function sqrt(
        uint256 value
    ) internal pure returns (uint256 result) {
        if (value == 0) return 0;

        uint256 estimate = 2 ** (log2(value) >> 1);
        unchecked {
            // Seven iterations are sufficient to converge for every uint256 input.
            estimate = (estimate + value / estimate) >> 1;
            estimate = (estimate + value / estimate) >> 1;
            estimate = (estimate + value / estimate) >> 1;
            estimate = (estimate + value / estimate) >> 1;
            estimate = (estimate + value / estimate) >> 1;
            estimate = (estimate + value / estimate) >> 1;
            estimate = (estimate + value / estimate) >> 1;
            result = min(estimate, value / estimate);
        }
    }

    /// @notice Returns floor(log2(value)), or zero for zero.
    function log2(
        uint256 value
    ) internal pure returns (uint256 result) {
        unchecked {
            if (value >> 128 != 0) {
                value >>= 128;
                result += 128;
            }
            if (value >> 64 != 0) {
                value >>= 64;
                result += 64;
            }
            if (value >> 32 != 0) {
                value >>= 32;
                result += 32;
            }
            if (value >> 16 != 0) {
                value >>= 16;
                result += 16;
            }
            if (value >> 8 != 0) {
                value >>= 8;
                result += 8;
            }
            if (value >> 4 != 0) {
                value >>= 4;
                result += 4;
            }
            if (value >> 2 != 0) {
                value >>= 2;
                result += 2;
            }
            if (value >> 1 != 0) result += 1;
        }
    }

    /// @notice Sorts two distinct, nonzero token addresses.
    function sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address token0, address token1) {
        if (tokenA == tokenB || tokenA == address(0) || tokenB == address(0)) revert ZeroAmount();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    /// @notice Quotes `amountA` at the current reserve ratio.
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        if (amountA == 0) revert ZeroAmount();
        if (reserveA == 0 || reserveB == 0) revert ZeroReserve();
        amountB = FullMath.mulDiv(amountA, reserveB, reserveA);
    }

    /// @notice Calculates initial LP shares and reserves a permanently locked minimum.
    function initialLiquidity(
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint256 liquidity) {
        if (amount0 == 0 || amount1 == 0) revert ZeroAmount();
        if (amount0 > type(uint256).max / amount1) revert ArithmeticOverflow();

        uint256 geometricMean = sqrt(amount0 * amount1);
        if (geometricMean <= MINIMUM_LIQUIDITY) revert InsufficientInitialLiquidity();
        unchecked {
            liquidity = geometricMean - MINIMUM_LIQUIDITY;
        }
    }

    /// @notice Calculates proportional LP shares for an established pool.
    function liquidityForAmounts(
        uint256 amount0,
        uint256 amount1,
        uint256 reserve0,
        uint256 reserve1,
        uint256 supply
    ) internal pure returns (uint256 liquidity) {
        if (amount0 == 0 || amount1 == 0 || supply == 0) revert ZeroAmount();
        if (reserve0 == 0 || reserve1 == 0) revert ZeroReserve();

        uint256 fromToken0 = FullMath.mulDiv(amount0, supply, reserve0);
        uint256 fromToken1 = FullMath.mulDiv(amount1, supply, reserve1);
        liquidity = min(fromToken0, fromToken1);
    }

    /// @notice Calculates proportional asset amounts represented by LP shares.
    function amountsForLiquidity(
        uint256 liquidity,
        uint256 supply,
        uint256 reserve0,
        uint256 reserve1
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        if (liquidity == 0 || supply == 0) revert ZeroAmount();
        amount0 = FullMath.mulDiv(liquidity, reserve0, supply);
        amount1 = FullMath.mulDiv(liquidity, reserve1, supply);
    }

    /// @notice Splits a gross swap fee into LP-owned and protocol-owned portions.
    function splitFee(
        uint256 amountIn,
        uint24 feePpm,
        uint24 protocolSharePpm
    ) internal pure returns (uint256 netAmountIn, uint256 lpFee, uint256 protocolFee) {
        if (feePpm >= FEE_DENOMINATOR) revert InvalidFee();
        if (protocolSharePpm > FEE_DENOMINATOR) revert InvalidProtocolShare();

        uint256 totalFee = FullMath.mulDiv(amountIn, feePpm, FEE_DENOMINATOR);
        protocolFee = FullMath.mulDiv(totalFee, protocolSharePpm, FEE_DENOMINATOR);
        unchecked {
            lpFee = totalFee - protocolFee;
            netAmountIn = amountIn - totalFee;
        }
    }

    /// @notice Measures the share of total reserves represented by their absolute difference.
    function imbalancePpm(
        uint256 reserve0,
        uint256 reserve1
    ) internal pure returns (uint256) {
        uint256 total = reserve0 + reserve1;
        if (total < reserve0) revert ArithmeticOverflow();
        if (total == 0) return 0;
        return FullMath.mulDiv(absDiff(reserve0, reserve1), FEE_DENOMINATOR, total);
    }

    /// @notice Converts a value to uint112, reverting instead of truncating.
    function toUint112(
        uint256 value
    ) internal pure returns (uint112 narrowed) {
        if (value > type(uint112).max) revert ArithmeticOverflow();
        // The explicit upper-bound check above makes this narrowing conversion safe.
        // forge-lint: disable-next-line(unsafe-typecast)
        narrowed = uint112(value);
    }

    /// @notice Converts a value to uint128, reverting instead of truncating.
    function toUint128(
        uint256 value
    ) internal pure returns (uint128 narrowed) {
        if (value > type(uint128).max) revert ArithmeticOverflow();
        // The explicit upper-bound check above makes this narrowing conversion safe.
        // forge-lint: disable-next-line(unsafe-typecast)
        narrowed = uint128(value);
    }
}
