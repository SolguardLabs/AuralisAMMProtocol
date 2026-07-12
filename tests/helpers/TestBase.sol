// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface Vm {
    function assume(
        bool condition
    ) external;
    function bound(
        uint256 value,
        uint256 minimum,
        uint256 maximum
    ) external pure returns (uint256 result);
    function expectRevert() external;
    function expectRevert(
        bytes4 selector
    ) external;
    function expectRevert(
        bytes calldata revertData
    ) external;
    function label(
        address account,
        string calldata newLabel
    ) external;
    function prank(
        address sender
    ) external;
    function startPrank(
        address sender
    ) external;
    function stopPrank() external;
    function warp(
        uint256 newTimestamp
    ) external;
}

abstract contract TestBase {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    error AssertionFailed();
    error AssertionEqUint(uint256 left, uint256 right);
    error AssertionEqAddress(address left, address right);
    error AssertionEqBool(bool left, bool right);
    error AssertionEqBytes32(bytes32 left, bytes32 right);
    error AssertionGreaterThan(uint256 left, uint256 right);
    error AssertionGreaterThanOrEqual(uint256 left, uint256 right);
    error AssertionLessThan(uint256 left, uint256 right);
    error AssertionLessThanOrEqual(uint256 left, uint256 right);
    error AssertionApproximate(uint256 left, uint256 right, uint256 tolerance);

    function assertTrue(
        bool condition
    ) internal pure {
        if (!condition) revert AssertionFailed();
    }

    function assertFalse(
        bool condition
    ) internal pure {
        if (condition) revert AssertionFailed();
    }

    function assertEq(
        uint256 left,
        uint256 right
    ) internal pure {
        if (left != right) revert AssertionEqUint(left, right);
    }

    function assertEq(
        address left,
        address right
    ) internal pure {
        if (left != right) revert AssertionEqAddress(left, right);
    }

    function assertEq(
        bool left,
        bool right
    ) internal pure {
        if (left != right) revert AssertionEqBool(left, right);
    }

    function assertEq(
        bytes32 left,
        bytes32 right
    ) internal pure {
        if (left != right) revert AssertionEqBytes32(left, right);
    }

    function assertGt(
        uint256 left,
        uint256 right
    ) internal pure {
        if (left <= right) revert AssertionGreaterThan(left, right);
    }

    function assertGe(
        uint256 left,
        uint256 right
    ) internal pure {
        if (left < right) revert AssertionGreaterThanOrEqual(left, right);
    }

    function assertLt(
        uint256 left,
        uint256 right
    ) internal pure {
        if (left >= right) revert AssertionLessThan(left, right);
    }

    function assertLe(
        uint256 left,
        uint256 right
    ) internal pure {
        if (left > right) revert AssertionLessThanOrEqual(left, right);
    }

    function assertApproxEqAbs(
        uint256 left,
        uint256 right,
        uint256 tolerance
    ) internal pure {
        uint256 difference = left > right ? left - right : right - left;
        if (difference > tolerance) revert AssertionApproximate(left, right, tolerance);
    }
}
