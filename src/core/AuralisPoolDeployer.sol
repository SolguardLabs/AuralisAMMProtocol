// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { AuralisPool } from "./AuralisPool.sol";

/// @title Auralis pool deployer
/// @notice Keeps pool creation bytecode outside the canonical registry runtime.
contract AuralisPoolDeployer {
    error OnlyFactory(address caller);

    address public immutable factory;

    constructor() {
        factory = msg.sender;
    }

    function deploy(
        address token0,
        address token1,
        address imbalanceGuard,
        bytes32 salt
    ) external returns (address pool) {
        if (msg.sender != factory) revert OnlyFactory(msg.sender);
        pool = address(new AuralisPool{ salt: salt }(factory, token0, token1, imbalanceGuard));
    }

    function computeAddress(
        address token0,
        address token1,
        address imbalanceGuard,
        bytes32 salt
    ) external view returns (address predicted) {
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(AuralisPool).creationCode, abi.encode(factory, token0, token1, imbalanceGuard)
            )
        );
        bytes32 digest = keccak256(abi.encodePacked(hex"ff", address(this), salt, initCodeHash));
        predicted = address(uint160(uint256(digest)));
    }
}
