// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { AuralisMath } from "./AuralisMath.sol";
import { FullMath } from "./FullMath.sol";

/// @title Pool reserve arithmetic
/// @notice Accounting and constant-product helpers for a two-asset Auralis pool.
library ReserveMath {
    uint256 internal constant PPM = 1_000_000;

    error InsufficientBalance(uint256 balance, uint256 excludedAmount);
    error InsufficientLiquidity();
    error InvalidSwapAmount();
    error ReserveLimitExceeded();
    error ImbalanceLimitExceeded(uint256 imbalancePpm, uint256 maximumPpm);

    /// @notice Fee amounts tracked separately from active swap reserves.
    struct FeeBalances {
        uint128 lpFee0;
        uint128 lpFee1;
        uint128 protocolFee0;
        uint128 protocolFee1;
    }

    /// @notice Calculates a balance after excluding separately accounted amounts.
    function balanceAfterExclusions(
        uint256 balance,
        uint256 firstExcluded,
        uint256 secondExcluded
    ) internal pure returns (uint256 available) {
        uint256 excluded = firstExcluded + secondExcluded;
        if (excluded < firstExcluded || balance < excluded) {
            revert InsufficientBalance(balance, excluded);
        }
        unchecked {
            available = balance - excluded;
        }
    }

    /// @notice Derives active reserves from token balances and all segregated fees.
    function activeReserves(
        uint256 balance0,
        uint256 balance1,
        FeeBalances memory fees
    ) internal pure returns (uint112 reserve0, uint112 reserve1) {
        uint256 available0 = balanceAfterExclusions(balance0, fees.lpFee0, fees.protocolFee0);
        uint256 available1 = balanceAfterExclusions(balance1, fees.lpFee1, fees.protocolFee1);
        if (available0 > type(uint112).max || available1 > type(uint112).max) {
            revert ReserveLimitExceeded();
        }
        // Both values were explicitly bounded to uint112 immediately above.
        // forge-lint: disable-next-line(unsafe-typecast)
        reserve0 = uint112(available0);
        // forge-lint: disable-next-line(unsafe-typecast)
        reserve1 = uint112(available1);
    }

    /// @notice Derives LP-owned balances by excluding only protocol-owned fees.
    function lpOwnedBalances(
        uint256 balance0,
        uint256 balance1,
        FeeBalances memory fees
    ) internal pure returns (uint256 owned0, uint256 owned1) {
        owned0 = balanceAfterExclusions(balance0, fees.protocolFee0, 0);
        owned1 = balanceAfterExclusions(balance1, fees.protocolFee1, 0);
    }

    /// @notice Returns the constant-product invariant for two reserves.
    function invariant(
        uint256 reserve0,
        uint256 reserve1
    ) internal pure returns (uint256 k) {
        if (reserve0 != 0 && reserve1 > type(uint256).max / reserve0) {
            revert ReserveLimitExceeded();
        }
        k = reserve0 * reserve1;
    }

    /// @notice Calculates exact-input output under the constant-product curve.
    /// @dev `netAmountIn` must already exclude the assessed swap fee.
    function amountOut(
        uint256 amountInAfterFee,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 output) {
        if (amountInAfterFee == 0) revert InvalidSwapAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        output = FullMath.mulDiv(amountInAfterFee, reserveOut, reserveIn + amountInAfterFee);
        if (output == 0 || output >= reserveOut) revert InvalidSwapAmount();
    }

    /// @notice Calculates the net input needed for an exact output under the curve.
    function netAmountIn(
        uint256 output,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 input) {
        if (output == 0 || output >= reserveOut) revert InvalidSwapAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        input = FullMath.mulDivRoundingUp(reserveIn, output, reserveOut - output);
    }

    /// @notice Calculates proportional withdrawal amounts from chosen accounting balances.
    function withdrawalAmounts(
        uint256 liquidity,
        uint256 supply,
        uint256 balance0,
        uint256 balance1
    ) internal pure returns (uint256 amount0, uint256 amount1) {
        if (liquidity == 0 || supply == 0 || liquidity > supply) {
            revert InsufficientLiquidity();
        }
        amount0 = FullMath.mulDiv(liquidity, balance0, supply);
        amount1 = FullMath.mulDiv(liquidity, balance1, supply);
        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidity();
    }

    /// @notice Enforces a maximum symmetric imbalance after a state transition.
    function validateImbalance(
        uint256 reserve0,
        uint256 reserve1,
        uint24 maximumImbalancePpm
    ) internal pure {
        if (maximumImbalancePpm > PPM) revert ImbalanceLimitExceeded(PPM, maximumImbalancePpm);
        uint256 measured = AuralisMath.imbalancePpm(reserve0, reserve1);
        if (measured > maximumImbalancePpm) {
            revert ImbalanceLimitExceeded(measured, maximumImbalancePpm);
        }
    }

    /// @notice Applies signed reserve deltas while preserving unsigned bounds.
    function applyDelta(
        uint112 reserve,
        int256 delta
    ) internal pure returns (uint112 updated) {
        uint256 value;
        if (delta >= 0) {
            // The branch condition proves that the signed value is nonnegative.
            // forge-lint: disable-next-line(unsafe-typecast)
            value = uint256(reserve) + uint256(delta);
        } else {
            if (delta == type(int256).min) revert InsufficientLiquidity();
            // Negation is safe after excluding int256.min and produces a positive value.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 decrease = uint256(-delta);
            if (decrease > reserve) revert InsufficientLiquidity();
            unchecked {
                value = uint256(reserve) - decrease;
            }
        }
        if (value > type(uint112).max) revert ReserveLimitExceeded();
        // The explicit upper-bound check above makes this narrowing conversion safe.
        // forge-lint: disable-next-line(unsafe-typecast)
        updated = uint112(value);
    }
}
