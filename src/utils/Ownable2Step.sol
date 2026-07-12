// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Two-step ownership
/// @notice Provides an owner role whose transfer must be accepted by the nominated account.
/// @dev The two-step flow prevents ownership from being lost to a mistyped address.
abstract contract Ownable2Step {
    /// @notice Reverts when an owner-only function is called by another account.
    error Unauthorized(address caller);

    /// @notice Reverts when an ownership role is assigned to the zero address.
    error InvalidOwner(address candidate);

    /// @notice Reverts when an account other than the nominee attempts acceptance.
    error NotPendingOwner(address caller, address pendingOwner);

    /// @notice Emitted when the current owner nominates a successor.
    event OwnershipTransferStarted(address indexed previousOwner, address indexed pendingOwner);

    /// @notice Emitted when an accepted ownership transfer takes effect.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    address private _owner;

    /// @notice Account nominated to become the next owner.
    address public pendingOwner;

    /// @param initialOwner Account receiving the owner role at deployment.
    constructor(
        address initialOwner
    ) {
        if (initialOwner == address(0)) revert InvalidOwner(initialOwner);
        _owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    /// @notice Account currently authorized to administer the contract.
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /// @notice Restricts a function to the current owner.
    modifier onlyOwner() {
        if (msg.sender != _owner) revert Unauthorized(msg.sender);
        _;
    }

    /// @notice Nominates `newOwner` to take ownership.
    /// @dev The nomination remains inactive until `newOwner` calls {acceptOwnership}.
    function transferOwnership(
        address newOwner
    ) external onlyOwner {
        if (newOwner == address(0)) revert InvalidOwner(newOwner);
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(_owner, newOwner);
    }

    /// @notice Accepts ownership when called by the nominated account.
    function acceptOwnership() external {
        address nominee = pendingOwner;
        if (msg.sender != nominee) revert NotPendingOwner(msg.sender, nominee);

        address previousOwner = _owner;
        _owner = nominee;
        pendingOwner = address(0);
        emit OwnershipTransferred(previousOwner, nominee);
    }
}
