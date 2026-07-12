// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { TestBase } from "./TestBase.sol";

abstract contract InvariantBase is TestBase {
    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    struct FuzzArtifactSelector {
        string artifact;
        bytes4[] selectors;
    }

    struct FuzzInterface {
        address addr;
        string[] artifacts;
    }

    address[] private _targetedContracts;
    address[] private _excludedContracts;
    address[] private _targetedSenders;
    address[] private _excludedSenders;
    string[] private _targetedArtifacts;
    string[] private _excludedArtifacts;
    FuzzSelector[] private _targetedSelectors;
    FuzzSelector[] private _excludedSelectors;
    FuzzArtifactSelector[] private _targetedArtifactSelectors;
    FuzzInterface[] private _targetedInterfaces;

    function targetContract(
        address target
    ) internal {
        _targetedContracts.push(target);
    }

    function targetContracts() public view returns (address[] memory) {
        return _targetedContracts;
    }

    function excludeContracts() public view returns (address[] memory) {
        return _excludedContracts;
    }

    function targetSenders() public view returns (address[] memory) {
        return _targetedSenders;
    }

    function excludeSenders() public view returns (address[] memory) {
        return _excludedSenders;
    }

    function targetArtifacts() public view returns (string[] memory) {
        return _targetedArtifacts;
    }

    function excludeArtifacts() public view returns (string[] memory) {
        return _excludedArtifacts;
    }

    function targetSelectors() public view returns (FuzzSelector[] memory) {
        return _targetedSelectors;
    }

    function excludeSelectors() public view returns (FuzzSelector[] memory) {
        return _excludedSelectors;
    }

    function targetArtifactSelectors() public view returns (FuzzArtifactSelector[] memory) {
        return _targetedArtifactSelectors;
    }

    function targetInterfaces() public view returns (FuzzInterface[] memory) {
        return _targetedInterfaces;
    }
}
