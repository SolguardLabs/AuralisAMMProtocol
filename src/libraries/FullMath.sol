// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Full precision arithmetic
/// @notice Performs multiplication and division without losing the high 256 bits of a product.
library FullMath {
    /// @notice Reverts when a division denominator is zero.
    error DivisionByZero();

    /// @notice Reverts when the exact result cannot be represented by a uint256.
    error ResultOverflow();

    /// @notice Calculates floor(x * y / denominator) with full intermediate precision.
    /// @dev The algorithm reconstructs the 512-bit product and performs exact modular division.
    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        unchecked {
            uint256 productLow;
            uint256 productHigh;

            assembly ("memory-safe") {
                let mm := mulmod(x, y, not(0))
                productLow := mul(x, y)
                productHigh := sub(sub(mm, productLow), lt(mm, productLow))
            }

            if (productHigh == 0) {
                if (denominator == 0) revert DivisionByZero();
                return productLow / denominator;
            }

            // The result is at least 2**256 when denominator is not above the high limb.
            if (denominator <= productHigh) {
                if (denominator == 0) revert DivisionByZero();
                revert ResultOverflow();
            }

            uint256 remainder;
            assembly ("memory-safe") {
                remainder := mulmod(x, y, denominator)
                productHigh := sub(productHigh, gt(remainder, productLow))
                productLow := sub(productLow, remainder)
            }

            // Factor powers of two from the denominator so the remaining divisor is odd.
            uint256 twos = denominator & (0 - denominator);
            assembly ("memory-safe") {
                denominator := div(denominator, twos)
                productLow := div(productLow, twos)
                twos := add(div(sub(0, twos), twos), 1)
            }

            productLow |= productHigh * twos;

            // Seed correct for four bits, then double precision through Newton-Raphson steps.
            uint256 inverse = (3 * denominator) ^ 2;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;

            result = productLow * inverse;
        }
    }

    /// @notice Calculates ceil(x * y / denominator) with full intermediate precision.
    function mulDivRoundingUp(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        result = mulDiv(x, y, denominator);
        if (mulmod(x, y, denominator) != 0) {
            if (result == type(uint256).max) revert ResultOverflow();
            unchecked {
                ++result;
            }
        }
    }

    /// @notice Calculates ceil(numerator / denominator).
    function divRoundingUp(
        uint256 numerator,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        if (denominator == 0) revert DivisionByZero();
        result = numerator / denominator;
        if (numerator % denominator != 0) {
            unchecked {
                ++result;
            }
        }
    }
}
