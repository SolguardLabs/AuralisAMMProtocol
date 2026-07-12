// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IAuralisFactory } from "../interfaces/IAuralisFactory.sol";
import { IAuralisPool } from "../interfaces/IAuralisPool.sol";
import { AuralisOracle } from "../oracle/AuralisOracle.sol";
import { Ownable2Step } from "../utils/Ownable2Step.sol";
import { AuralisPoolDeployer } from "./AuralisPoolDeployer.sol";

interface AuralisPoolLike {
    function setOracle(
        address newOracle
    ) external;
}

/// @title Auralis canonical pool factory
/// @notice Deterministically deploys two-token pools and their price oracles.
contract AuralisFactory is IAuralisFactory, Ownable2Step {
    event OracleObservationIntervalUpdated(uint32 previousInterval, uint32 newInterval);

    address public immutable override imbalanceGuard;
    AuralisPoolDeployer public immutable poolDeployer;

    address public override feeController;
    address public override protocolFeeRecipient;
    address public override guardian;
    uint32 public oracleObservationInterval;
    bool public override creationPaused;

    mapping(address tokenA => mapping(address tokenB => address pool)) private _poolFor;
    mapping(address pool => bool canonical) public override isPool;
    mapping(address pool => address oracle) public override poolOracle;
    address[] private _allPools;

    constructor(
        address initialOwner,
        address imbalanceGuard_,
        address initialFeeController,
        address initialProtocolFeeRecipient,
        address initialGuardian,
        uint32 initialOracleObservationInterval
    ) Ownable2Step(initialOwner) {
        if (imbalanceGuard_ == address(0) || initialProtocolFeeRecipient == address(0)) {
            revert ZeroAddress();
        }
        if (imbalanceGuard_.code.length == 0) revert InvalidContract(imbalanceGuard_);
        _validateOptionalContract(initialFeeController);
        if (initialOracleObservationInterval == 0) revert InvalidObservationInterval();

        imbalanceGuard = imbalanceGuard_;
        feeController = initialFeeController;
        protocolFeeRecipient = initialProtocolFeeRecipient;
        guardian = initialGuardian;
        oracleObservationInterval = initialOracleObservationInterval;
        poolDeployer = new AuralisPoolDeployer();
    }

    function owner() public view override(IAuralisFactory, Ownable2Step) returns (address) {
        return Ownable2Step.owner();
    }

    function getPool(
        address tokenA,
        address tokenB
    ) external view override returns (address pool) {
        pool = _poolFor[tokenA][tokenB];
    }

    function allPools(
        uint256 index
    ) external view override returns (address pool) {
        pool = _allPools[index];
    }

    function allPoolsLength() external view override returns (uint256) {
        return _allPools.length;
    }

    function pairSalt(
        address tokenA,
        address tokenB
    ) public pure returns (bytes32 salt) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        salt = keccak256(abi.encodePacked(token0, token1));
    }

    function predictPoolAddress(
        address tokenA,
        address tokenB
    ) external view override returns (address predicted) {
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        predicted = poolDeployer.computeAddress(token0, token1, imbalanceGuard, salt);
    }

    function createPool(
        address tokenA,
        address tokenB
    ) external override returns (address pool) {
        if (creationPaused) revert PoolCreationPaused();
        (address token0, address token1) = _sortTokens(tokenA, tokenB);
        if (token0.code.length == 0) revert InvalidContract(token0);
        if (token1.code.length == 0) revert InvalidContract(token1);
        if (_poolFor[token0][token1] != address(0)) {
            revert PoolAlreadyExists(token0, token1);
        }

        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        pool = poolDeployer.deploy(token0, token1, imbalanceGuard, salt);
        bytes32 oracleSalt = keccak256(abi.encodePacked("AURALIS_ORACLE", salt));
        address oracle =
            address(new AuralisOracle{ salt: oracleSalt }(pool, oracleObservationInterval));
        AuralisPoolLike(pool).setOracle(oracle);

        _poolFor[token0][token1] = pool;
        _poolFor[token1][token0] = pool;
        isPool[pool] = true;
        poolOracle[pool] = oracle;
        _allPools.push(pool);

        emit PoolOracleUpdated(pool, address(0), oracle);
        emit PoolCreated(token0, token1, pool, _allPools.length);
    }

    function setFeeController(
        address newController
    ) external override onlyOwner {
        _validateOptionalContract(newController);
        address previousController = feeController;
        feeController = newController;
        emit FeeControllerUpdated(previousController, newController);
    }

    function setProtocolFeeRecipient(
        address newRecipient
    ) external override onlyOwner {
        if (newRecipient == address(0)) revert ZeroAddress();
        address previousRecipient = protocolFeeRecipient;
        protocolFeeRecipient = newRecipient;
        emit ProtocolFeeRecipientUpdated(previousRecipient, newRecipient);
    }

    function setGuardian(
        address newGuardian
    ) external override onlyOwner {
        address previousGuardian = guardian;
        guardian = newGuardian;
        emit GuardianUpdated(previousGuardian, newGuardian);
    }

    function setOracleObservationInterval(
        uint32 newInterval
    ) external onlyOwner {
        if (newInterval == 0) revert InvalidObservationInterval();
        uint32 previousInterval = oracleObservationInterval;
        oracleObservationInterval = newInterval;
        emit OracleObservationIntervalUpdated(previousInterval, newInterval);
    }

    function setCreationPaused(
        bool newPaused
    ) external override {
        _authorizePause(newPaused);
        creationPaused = newPaused;
        emit PoolCreationPauseUpdated(newPaused);
    }

    function setPoolPaused(
        address pool,
        bool newPaused
    ) external override {
        _authorizePause(newPaused);
        _requirePool(pool);
        IAuralisPool(pool).setPaused(newPaused);
        emit PoolPauseUpdated(pool, newPaused, msg.sender);
    }

    function setPoolOracle(
        address pool,
        address newOracle
    ) external override onlyOwner {
        _requirePool(pool);
        _validateOptionalContract(newOracle);
        address previousOracle = poolOracle[pool];
        AuralisPoolLike(pool).setOracle(newOracle);
        poolOracle[pool] = newOracle;
        emit PoolOracleUpdated(pool, previousOracle, newOracle);
    }

    function _authorizePause(
        bool newPaused
    ) internal view {
        if (msg.sender == owner()) return;
        if (msg.sender != guardian) revert Unauthorized(msg.sender);
        if (!newPaused) revert GuardianCannotUnpause();
    }

    function _requirePool(
        address pool
    ) internal view {
        if (!isPool[pool]) revert UnknownPool(pool);
    }

    function _validateOptionalContract(
        address candidate
    ) internal view {
        if (candidate != address(0) && candidate.code.length == 0) {
            revert InvalidContract(candidate);
        }
    }

    function _sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address token0, address token1) {
        if (tokenA == address(0) || tokenB == address(0)) revert ZeroAddress();
        if (tokenA == tokenB) revert IdenticalTokens();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }
}
