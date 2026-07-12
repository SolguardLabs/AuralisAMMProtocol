// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice The caller is not permitted to execute the requested action.
error AuralisUnauthorized(address caller);

/// @notice An address parameter cannot be zero.
error AuralisZeroAddress();

/// @notice An amount parameter cannot be zero.
error AuralisZeroAmount();

/// @notice The transaction was submitted after its declared deadline.
error AuralisDeadlineExpired(uint256 deadline, uint256 currentTimestamp);

/// @notice The supplied pool is not registered by the canonical factory.
error AuralisUnknownPool(address pool);

/// @notice The selected token does not belong to the pool.
error AuralisInvalidToken(address token);

/// @notice A route does not connect its adjacent assets.
error AuralisInvalidRoute(uint256 step);

/// @notice The pool has not received its initial liquidity.
error AuralisPoolNotInitialized();

/// @notice The operation is disabled while the pool is paused.
error AuralisPoolPaused();

/// @notice The amount received from a token differs from the requested transfer.
error AuralisUnsupportedToken(address token, uint256 expected, uint256 received);

/// @notice Available liquidity is insufficient for the requested operation.
error AuralisInsufficientLiquidity();

/// @notice Minted shares are below the caller's limit.
error AuralisInsufficientShares(uint256 minimum, uint256 actual);

/// @notice The first asset output is below its slippage limit.
error AuralisAmount0BelowMinimum(uint256 minimum, uint256 actual);

/// @notice The second asset output is below its slippage limit.
error AuralisAmount1BelowMinimum(uint256 minimum, uint256 actual);

/// @notice Swap output is below its slippage limit.
error AuralisOutputBelowMinimum(uint256 minimum, uint256 actual);

/// @notice The projected pool composition exceeds the configured risk band.
error AuralisImbalanceExceeded(uint256 measuredPpm, uint256 maximumPpm);

/// @notice A projected active reserve is below the configured minimum.
error AuralisReserveBelowMinimum(uint256 reserve, uint256 minimum);

/// @notice A value cannot be represented by the target storage type.
error AuralisCastOverflow(uint256 value, uint256 maximum);

/// @notice The physical balance does not cover all separately tracked obligations.
error AuralisAccountingDeficit(address token, uint256 balance, uint256 obligations);

/// @notice The requested observation is outside the retained history.
error AuralisObservationUnavailable(uint32 secondsAgo);

/// @notice Configuration values are outside the supported domain.
error AuralisInvalidConfiguration();

/// @notice A state transition would create a duplicate canonical pool.
error AuralisPoolAlreadyExists(address token0, address token1);

/// @notice A direct native-currency transfer is not accepted.
error AuralisNativeTransferRejected();

/// @notice A callback or nested entry attempted to reenter protected state.
error AuralisReentrancy();

