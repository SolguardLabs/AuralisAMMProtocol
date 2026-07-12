// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface VmDeployAuralis {
    function addr(
        uint256 privateKey
    ) external returns (address keyAddr);

    function envUint(
        string calldata name
    ) external returns (uint256 value);

    function envOr(
        string calldata name,
        address defaultValue
    ) external returns (address value);

    function envOr(
        string calldata name,
        uint256 defaultValue
    ) external returns (uint256 value);

    function getCode(
        string calldata artifactPath
    ) external returns (bytes memory creationBytecode);

    function startBroadcast(
        uint256 privateKey
    ) external;

    function stopBroadcast() external;
}

/// @notice Deploys the shared policy contracts and canonical Auralis factory.
contract DeployAuralis {
    error ObservationIntervalTooLarge(uint256 interval);
    error DeploymentFailed(string artifact);

    event AuralisDeployed(
        address indexed factory,
        address indexed feeController,
        address indexed imbalanceGuard,
        address owner,
        address guardian,
        address protocolFeeRecipient
    );

    VmDeployAuralis private constant VM =
        VmDeployAuralis(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run()
        external
        returns (address factory, address feeController, address imbalanceGuard)
    {
        uint256 privateKey = VM.envUint("PRIVATE_KEY");
        address broadcaster = VM.addr(privateKey);
        address admin = VM.envOr("AURALIS_ADMIN", broadcaster);
        address guardian = VM.envOr("AURALIS_GUARDIAN", admin);
        address feeRecipient = VM.envOr("PROTOCOL_FEE_RECIPIENT", admin);
        uint256 interval = VM.envOr("ORACLE_OBSERVATION_INTERVAL", uint256(60));
        if (interval == 0 || interval > type(uint32).max) {
            revert ObservationIntervalTooLarge(interval);
        }

        VM.startBroadcast(privateKey);
        imbalanceGuard = _deploy("src/risk/ImbalanceGuard.sol:ImbalanceGuard", abi.encode(admin));
        feeController =
            _deploy("src/fees/DynamicFeeController.sol:DynamicFeeController", abi.encode(admin));
        // The interval was bounded to uint32 above.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint32 oracleInterval = uint32(interval);
        factory = _deploy(
            "src/core/AuralisFactory.sol:AuralisFactory",
            abi.encode(admin, imbalanceGuard, feeController, feeRecipient, guardian, oracleInterval)
        );
        VM.stopBroadcast();

        emit AuralisDeployed(factory, feeController, imbalanceGuard, admin, guardian, feeRecipient);
    }

    function _deploy(
        string memory artifact,
        bytes memory constructorArguments
    ) internal returns (address deployed) {
        bytes memory creationCode = abi.encodePacked(VM.getCode(artifact), constructorArguments);
        assembly ("memory-safe") {
            deployed := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        if (deployed == address(0)) revert DeploymentFailed(artifact);
    }
}
