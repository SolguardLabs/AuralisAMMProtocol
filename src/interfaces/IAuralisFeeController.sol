// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Auralis fee controller interface
/// @notice Quotes adaptive LP and protocol fees for Auralis pools.
interface IAuralisFeeController {
    /// @notice One million parts represents one hundred percent.
    function FEE_DENOMINATOR() external view returns (uint24);

    /// @notice Returns the account allowed to update fee parameters.
    function owner() external view returns (address);

    /// @notice Returns the lowest LP fee the controller may quote, in ppm.
    function minimumFee() external view returns (uint24);

    /// @notice Returns the highest LP fee the controller may quote, in ppm.
    function maximumFee() external view returns (uint24);

    /// @notice Returns the protocol share of the assessed fee, in ppm.
    function protocolFeeShare() external view returns (uint24);

    /// @notice Quotes fees for a prospective exact-input swap.
    /// @param pool Pool requesting the quote.
    /// @param zeroForOne True when token0 is supplied for token1.
    /// @param amountIn Gross input amount.
    /// @param reserveIn Current input-side effective reserve.
    /// @param reserveOut Current output-side effective reserve.
    /// @return lpFeePpm Total swap fee directed to liquidity providers, in ppm.
    /// @return protocolSharePpm Share of `lpFeePpm` directed to the protocol, in ppm.
    function quoteFee(
        address pool,
        bool zeroForOne,
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external view returns (uint24 lpFeePpm, uint24 protocolSharePpm);
}
