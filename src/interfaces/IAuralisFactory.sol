// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Auralis factory interface
/// @notice Registry, deployment and policy surface for canonical Auralis pools.
interface IAuralisFactory {
    /// @notice Emitted after a canonical pool is deployed.
    event PoolCreated(
        address indexed token0, address indexed token1, address indexed pool, uint256 poolCount
    );

    /// @notice Emitted after the oracle associated with a pool changes.
    event PoolOracleUpdated(
        address indexed pool, address indexed previousOracle, address indexed newOracle
    );

    /// @notice Emitted when the fee controller changes.
    event FeeControllerUpdated(address indexed previousController, address indexed newController);

    /// @notice Emitted when the protocol fee recipient changes.
    event ProtocolFeeRecipientUpdated(
        address indexed previousRecipient, address indexed newRecipient
    );

    /// @notice Emitted when the emergency guardian changes.
    event GuardianUpdated(address indexed previousGuardian, address indexed newGuardian);

    /// @notice Emitted when creation of new pools is paused or resumed.
    event PoolCreationPauseUpdated(bool paused);

    /// @notice Emitted after the pause state of a canonical pool changes.
    event PoolPauseUpdated(address indexed pool, bool paused, address indexed caller);

    /// @notice Reverts when both pool assets are the same token.
    error IdenticalTokens();

    /// @notice Reverts when a required address is zero.
    error ZeroAddress();

    /// @notice Reverts when an address expected to contain bytecode does not.
    error InvalidContract(address candidate);

    /// @notice Reverts when a pool is already registered for the token pair.
    error PoolAlreadyExists(address token0, address token1);

    /// @notice Reverts when an administrative action references a non-canonical pool.
    error UnknownPool(address pool);

    /// @notice Reverts when pool creation is disabled.
    error PoolCreationPaused();

    /// @notice Reverts when the guardian attempts to restore operations.
    error GuardianCannotUnpause();

    /// @notice Reverts when the oracle observation interval is zero.
    error InvalidObservationInterval();

    /// @notice Returns the factory owner.
    function owner() external view returns (address);

    /// @notice Returns the controller used to quote swap fees.
    function feeController() external view returns (address);

    /// @notice Returns the address that receives protocol-owned fees.
    function protocolFeeRecipient() external view returns (address);

    /// @notice Returns the emergency guardian.
    function guardian() external view returns (address);

    /// @notice Returns the reserve-composition guard shared by factory pools.
    function imbalanceGuard() external view returns (address);

    /// @notice Returns whether creation of new pools is paused.
    function creationPaused() external view returns (bool);

    /// @notice Returns the canonical pool for an unordered token pair, if any.
    function getPool(
        address tokenA,
        address tokenB
    ) external view returns (address pool);

    /// @notice Returns whether `pool` belongs to the canonical registry.
    function isPool(
        address pool
    ) external view returns (bool canonical);

    /// @notice Returns the oracle attached to a canonical pool.
    function poolOracle(
        address pool
    ) external view returns (address oracle);

    /// @notice Returns a pool from the enumerable registry.
    function allPools(
        uint256 index
    ) external view returns (address pool);

    /// @notice Returns the number of canonical pools.
    function allPoolsLength() external view returns (uint256);

    /// @notice Predicts the deterministic pool address for an unordered token pair.
    function predictPoolAddress(
        address tokenA,
        address tokenB
    ) external view returns (address predicted);

    /// @notice Deploys and registers a pool for an unordered token pair.
    function createPool(
        address tokenA,
        address tokenB
    ) external returns (address pool);

    /// @notice Sets the controller used by pools to quote fees.
    function setFeeController(
        address newController
    ) external;

    /// @notice Sets the protocol fee recipient.
    function setProtocolFeeRecipient(
        address newRecipient
    ) external;

    /// @notice Sets the emergency guardian. The zero address disables the role.
    function setGuardian(
        address newGuardian
    ) external;

    /// @notice Pauses or resumes creation of new pools.
    function setCreationPaused(
        bool newPaused
    ) external;

    /// @notice Pauses or resumes a canonical pool.
    function setPoolPaused(
        address pool,
        bool newPaused
    ) external;

    /// @notice Attaches a compatible oracle to a canonical pool.
    function setPoolOracle(
        address pool,
        address newOracle
    ) external;
}
