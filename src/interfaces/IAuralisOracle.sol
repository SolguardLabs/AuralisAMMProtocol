// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Auralis time-weighted price oracle interface
/// @notice Records cumulative pool prices and exposes bounded historical quotes.
interface IAuralisOracle {
    /// @notice A compact historical accumulator checkpoint.
    struct Observation {
        uint32 timestamp;
        uint224 price0Cumulative;
        uint224 price1Cumulative;
    }

    /// @notice Emitted whenever the oracle stores a new checkpoint.
    event ObservationRecorded(
        address indexed pool,
        uint16 indexed index,
        uint32 timestamp,
        uint224 price0Cumulative,
        uint224 price1Cumulative
    );

    /// @notice Returns the pool associated with the oracle.
    function pool() external view returns (address);

    /// @notice Returns the number of initialized observations.
    function cardinality() external view returns (uint16);

    /// @notice Returns the next observation slot to be written.
    function observationIndex() external view returns (uint16);

    /// @notice Returns an observation from the circular history buffer.
    function observations(
        uint256 index
    ) external view returns (uint32 timestamp, uint224 price0Cumulative, uint224 price1Cumulative);

    /// @notice Stores a checkpoint derived from current pool reserves.
    /// @return wrote True when a new observation was stored.
    function update(
        uint112 reserve0,
        uint112 reserve1
    ) external returns (bool wrote);

    /// @notice Quotes `amountIn` using a time-weighted price ending at the latest checkpoint.
    /// @param tokenIn Pool asset used as the quote input.
    /// @param amountIn Amount of `tokenIn` to value.
    /// @param secondsAgo Length of the averaging interval.
    /// @return amountOut Time-weighted amount of the opposite pool asset.
    function consult(
        address tokenIn,
        uint256 amountIn,
        uint32 secondsAgo
    ) external view returns (uint256 amountOut);
}
