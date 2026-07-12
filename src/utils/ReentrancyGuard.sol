// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Reentrancy guard
/// @notice Protects state-changing entry points from nested execution.
abstract contract ReentrancyGuard {
    /// @notice Reverts when a protected function is entered recursively.
    error ReentrantCall();

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _reentrancyStatus = _NOT_ENTERED;

    /// @notice Prevents direct and indirect reentrant calls to a function.
    modifier nonReentrant() {
        if (_reentrancyStatus == _ENTERED) revert ReentrantCall();
        _reentrancyStatus = _ENTERED;
        _;
        _reentrancyStatus = _NOT_ENTERED;
    }

    /// @notice Returns true while a protected call is being executed.
    /// @dev Intended for inheriting contracts that need to coordinate internal hooks.
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _reentrancyStatus == _ENTERED;
    }
}
