// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20Minimal } from "../interfaces/IERC20Minimal.sol";

/// @title Safe ERC-20 transfers
/// @notice Handles tokens that return true, return no data, or require allowance resets.
library SafeTransferLib {
    error TokenHasNoCode(address token);
    error TransferFailed(address token, address to, uint256 amount);
    error TransferFromFailed(address token, address from, address to, uint256 amount);
    error ApprovalFailed(address token, address spender, uint256 amount);
    error BalanceQueryFailed(address token, address account);

    /// @notice Safely transfers `amount` tokens from this contract to `to`.
    function safeTransfer(
        address token,
        address to,
        uint256 amount
    ) internal {
        _requireContract(token);
        (bool success, bytes memory returnData) =
            token.call(abi.encodeCall(IERC20Minimal.transfer, (to, amount)));
        if (!success || !_returnedTrueOrEmpty(returnData)) {
            revert TransferFailed(token, to, amount);
        }
    }

    /// @notice Safely transfers `amount` tokens from `from` to `to`.
    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        _requireContract(token);
        (bool success, bytes memory returnData) =
            token.call(abi.encodeCall(IERC20Minimal.transferFrom, (from, to, amount)));
        if (!success || !_returnedTrueOrEmpty(returnData)) {
            revert TransferFromFailed(token, from, to, amount);
        }
    }

    /// @notice Safely sets `spender`'s allowance to `amount`.
    /// @dev Use `forceApprove` for tokens that reject nonzero-to-nonzero allowance changes.
    function safeApprove(
        address token,
        address spender,
        uint256 amount
    ) internal {
        _requireContract(token);
        if (!_callApprove(token, spender, amount)) {
            revert ApprovalFailed(token, spender, amount);
        }
    }

    /// @notice Sets an allowance, first resetting it when the direct approval fails.
    function forceApprove(
        address token,
        address spender,
        uint256 amount
    ) internal {
        _requireContract(token);
        if (_callApprove(token, spender, amount)) return;
        if (!_callApprove(token, spender, 0) || !_callApprove(token, spender, amount)) {
            revert ApprovalFailed(token, spender, amount);
        }
    }

    /// @notice Reads an ERC-20 balance and rejects malformed return data.
    function safeBalanceOf(
        address token,
        address account
    ) internal view returns (uint256 balance) {
        _requireContract(token);
        (bool success, bytes memory returnData) =
            token.staticcall(abi.encodeCall(IERC20Minimal.balanceOf, (account)));
        if (!success || returnData.length < 32) revert BalanceQueryFailed(token, account);
        balance = abi.decode(returnData, (uint256));
    }

    function _callApprove(
        address token,
        address spender,
        uint256 amount
    ) private returns (bool) {
        (bool success, bytes memory returnData) =
            token.call(abi.encodeCall(IERC20Minimal.approve, (spender, amount)));
        return success && _returnedTrueOrEmpty(returnData);
    }

    function _returnedTrueOrEmpty(
        bytes memory returnData
    ) private pure returns (bool) {
        if (returnData.length == 0) return true;
        if (returnData.length < 32) return false;

        uint256 returnedValue;
        assembly ("memory-safe") {
            returnedValue := mload(add(returnData, 0x20))
        }
        return returnedValue == 1;
    }

    function _requireContract(
        address token
    ) private view {
        if (token.code.length == 0) revert TokenHasNoCode(token);
    }
}
