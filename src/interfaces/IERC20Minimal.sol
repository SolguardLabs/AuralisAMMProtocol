// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Minimal ERC-20 interface
/// @notice ERC-20 surface used by Auralis contracts when interacting with assets.
interface IERC20Minimal {
    /// @notice Emitted when `value` tokens move from `from` to `to`.
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice Emitted when `owner` sets `spender`'s allowance to `value`.
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @notice Returns the number of tokens in existence.
    function totalSupply() external view returns (uint256);

    /// @notice Returns the token balance owned by `account`.
    function balanceOf(
        address account
    ) external view returns (uint256);

    /// @notice Returns the remaining allowance from `owner` to `spender`.
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    /// @notice Approves `spender` to spend up to `value` tokens.
    /// @return success True when the approval succeeds.
    function approve(
        address spender,
        uint256 value
    ) external returns (bool success);

    /// @notice Transfers `value` tokens to `to`.
    /// @return success True when the transfer succeeds.
    function transfer(
        address to,
        uint256 value
    ) external returns (bool success);

    /// @notice Transfers `value` tokens from `from` to `to` using an allowance.
    /// @return success True when the transfer succeeds.
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool success);
}
