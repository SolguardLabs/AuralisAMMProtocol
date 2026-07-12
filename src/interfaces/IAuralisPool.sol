// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Auralis pool interface
/// @notice External surface for two-asset constant-product liquidity pools.
interface IAuralisPool {
    /// @notice Emitted after liquidity is issued.
    event Mint(
        address indexed sender,
        address indexed recipient,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );

    /// @notice Emitted after liquidity is redeemed.
    event Burn(
        address indexed sender,
        address indexed recipient,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity
    );

    /// @notice Emitted after a swap settles.
    event Swap(
        address indexed sender,
        address indexed recipient,
        address indexed tokenIn,
        uint256 amountIn,
        uint256 amountOut,
        uint256 lpFee,
        uint256 protocolFee
    );

    /// @notice Emitted after stored reserves are synchronized.
    event Sync(uint112 reserve0, uint112 reserve1);

    /// @notice Emitted when protocol fees are collected.
    event ProtocolFeesCollected(address indexed recipient, uint256 amount0, uint256 amount1);

    /// @notice Emitted when an LP claims fees attributed to its shares.
    event FeesClaimed(
        address indexed owner, address indexed recipient, uint256 amount0, uint256 amount1
    );

    /// @notice Emitted when the pool pause state changes.
    event PauseStateUpdated(bool paused);

    /// @notice Returns the factory that deployed the pool.
    function factory() external view returns (address);

    /// @notice Returns the lower-address pool asset.
    function token0() external view returns (address);

    /// @notice Returns the higher-address pool asset.
    function token1() external view returns (address);

    /// @notice Returns the time-weighted price oracle, if configured.
    function oracle() external view returns (address);

    /// @notice Returns true when swaps and liquidity changes are paused.
    function paused() external view returns (bool);

    /// @notice Returns the maximum permitted symmetric reserve imbalance, in ppm.
    function maxImbalancePpm() external view returns (uint24);

    /// @notice Returns the minimum active amount required for each reserve.
    function minimumReserve() external view returns (uint112);

    /// @notice Returns reserves and the timestamp of the last reserve update.
    function getReserves()
        external
        view
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    /// @notice Returns reserves used by the swap curve after accounting exclusions.
    function activeReserves() external view returns (uint112 reserve0, uint112 reserve1);

    /// @notice Returns fees accrued for liquidity providers but not yet realized.
    function pendingLPFees() external view returns (uint128 fee0, uint128 fee1);

    /// @notice Returns protocol-owned fees held by the pool.
    function protocolFees() external view returns (uint128 fee0, uint128 fee1);

    /// @notice Returns global fee growth per LP share in Q128 fixed-point form.
    function feeGrowthGlobalX128() external view returns (uint256 growth0, uint256 growth1);

    /// @notice Returns the fee-growth checkpoint most recently recorded for `owner`.
    function feeGrowthCheckpoint(
        address owner
    ) external view returns (uint256 growth0, uint256 growth1);

    /// @notice Returns currently claimable fees attributed to `owner`'s LP shares.
    function accruedFees(
        address owner
    ) external view returns (uint256 amount0, uint256 amount1);

    /// @notice Previews accepted deposits and LP shares for a mint request.
    function previewMint(
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external view returns (uint256 amount0, uint256 amount1, uint256 liquidity);

    /// @notice Previews assets returned when burning `owner`'s LP shares.
    function previewBurn(
        address owner,
        uint256 liquidity
    ) external view returns (uint256 amount0, uint256 amount1);

    /// @notice Supplies both assets and mints pool shares to `recipient`.
    /// @return amount0 Amount of token0 accepted by the pool.
    /// @return amount1 Amount of token1 accepted by the pool.
    /// @return liquidity Number of pool shares minted.
    function mint(
        address recipient,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Minimum,
        uint256 amount1Minimum,
        uint256 deadline
    ) external returns (uint256 amount0, uint256 amount1, uint256 liquidity);

    /// @notice Burns pool shares and sends the underlying assets to `recipient`.
    /// @return amount0 Amount of token0 returned.
    /// @return amount1 Amount of token1 returned.
    function burn(
        address owner,
        address recipient,
        uint256 liquidity,
        uint256 amount0Minimum,
        uint256 amount1Minimum,
        uint256 deadline
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Executes an exact-input swap.
    /// @param tokenIn Asset transferred into the pool.
    /// @param amountIn Gross input amount.
    /// @param amountOutMinimum Minimum acceptable output.
    /// @param recipient Address receiving the output asset.
    /// @return amountOut Output amount sent to `recipient`.
    function swapExactInput(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amountOut);

    /// @notice Quotes the current exact-input swap output and fee amounts.
    function quoteExactInput(
        address tokenIn,
        uint256 amountIn
    ) external view returns (uint256 amountOut, uint256 lpFee, uint256 protocolFee);

    /// @notice Transfers protocol-owned fees to the configured recipient.
    function collectProtocolFees() external returns (uint256 amount0, uint256 amount1);

    /// @notice Claims fees attributed to the caller's current and historical shares.
    function claimFees(
        address recipient
    ) external returns (uint256 amount0, uint256 amount1);

    /// @notice Sends balances exceeding accounted reserves and fees to `recipient`.
    function skim(
        address recipient
    ) external;

    /// @notice Synchronizes stored reserves to the pool's accounted balances.
    function sync() external;

    /// @notice Updates the emergency pause state.
    function setPaused(
        bool newPaused
    ) external;
}
