// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IAuralisOracle } from "../interfaces/IAuralisOracle.sol";
import { IAuralisPool } from "../interfaces/IAuralisPool.sol";
import { FullMath } from "../libraries/FullMath.sol";

/// @title Auralis cumulative-price oracle
/// @notice Maintains a bounded observation ring for TWAP quotes and volatility estimates.
/// @dev Price zero is token1 per token0; price one is token0 per token1. Both use Q112.
contract AuralisOracle is IAuralisOracle {
    /// @notice Reverts when any account other than the associated pool calls update.
    error OnlyPool(address caller);

    /// @notice Reverts when a zero pool address or interval is supplied.
    error InvalidConfiguration();

    /// @notice Reverts before enough observations cover a requested window.
    error InsufficientHistory(uint32 requestedSecondsAgo, uint32 availableSeconds);

    /// @notice Reverts for a zero averaging window.
    error InvalidWindow();

    /// @notice Reverts when a quote asset does not belong to the pool.
    error InvalidToken(address token);

    /// @notice Number of checkpoints retained by the circular buffer.
    uint16 public constant OBSERVATION_CAPACITY = 64;

    /// @notice One unit in the fixed-point representation used for prices.
    uint256 private constant Q112 = 1 << 112;

    /// @notice One million parts represents one hundred percent.
    uint256 private constant PPM = 1_000_000;

    /// @inheritdoc IAuralisOracle
    address public immutable override pool;

    /// @notice Minimum time between persisted checkpoints.
    uint32 public immutable minimumObservationInterval;

    /// @inheritdoc IAuralisOracle
    uint16 public override cardinality;

    /// @inheritdoc IAuralisOracle
    uint16 public override observationIndex;

    /// @inheritdoc IAuralisOracle
    Observation[OBSERVATION_CAPACITY] public override observations;

    /// @notice Latest running token1-per-token0 accumulator.
    uint224 public price0Cumulative;

    /// @notice Latest running token0-per-token1 accumulator.
    uint224 public price1Cumulative;

    uint112 private _lastReserve0;
    uint112 private _lastReserve1;
    uint32 private _lastUpdateTimestamp;
    bool private _initialized;

    /// @param pool_ Pool allowed to append reserve updates.
    /// @param minimumObservationInterval_ Minimum persistence interval in seconds.
    constructor(
        address pool_,
        uint32 minimumObservationInterval_
    ) {
        if (pool_ == address(0) || minimumObservationInterval_ == 0) {
            revert InvalidConfiguration();
        }
        pool = pool_;
        minimumObservationInterval = minimumObservationInterval_;
    }

    /// @inheritdoc IAuralisOracle
    function update(
        uint112 reserve0,
        uint112 reserve1
    ) external override returns (bool wrote) {
        if (msg.sender != pool) revert OnlyPool(msg.sender);
        uint32 timestamp = uint32(block.timestamp);

        if (!_initialized) {
            _initialized = true;
            _lastUpdateTimestamp = timestamp;
            _lastReserve0 = reserve0;
            _lastReserve1 = reserve1;
            _record(timestamp, 0, 0);
            return true;
        }

        _accumulate(timestamp);
        _lastReserve0 = reserve0;
        _lastReserve1 = reserve1;

        Observation memory latest = _latest();
        if (uint32(timestamp - latest.timestamp) < minimumObservationInterval) return false;
        _record(timestamp, price0Cumulative, price1Cumulative);
        wrote = true;
    }

    /// @inheritdoc IAuralisOracle
    function consult(
        address tokenIn,
        uint256 amountIn,
        uint32 secondsAgo
    ) external view override returns (uint256 amountOut) {
        if (secondsAgo == 0) revert InvalidWindow();
        Observation memory latest = _latestOrRevert(secondsAgo);
        (uint224 target0, uint224 target1) =
            _cumulativeAt(latest.timestamp - secondsAgo, secondsAgo);

        address token0 = IAuralisPool(pool).token0();
        uint256 averagePriceX112;
        if (tokenIn == token0) {
            averagePriceX112 = uint256(_delta(latest.price0Cumulative, target0)) / secondsAgo;
        } else if (tokenIn == IAuralisPool(pool).token1()) {
            averagePriceX112 = uint256(_delta(latest.price1Cumulative, target1)) / secondsAgo;
        } else {
            revert InvalidToken(tokenIn);
        }
        amountOut = FullMath.mulDiv(amountIn, averagePriceX112, Q112);
    }

    /// @notice Returns cumulative prices at a historical offset from the latest checkpoint.
    function observe(
        uint32 secondsAgo
    ) external view returns (uint224 cumulative0, uint224 cumulative1) {
        Observation memory latest = _latestOrRevert(secondsAgo);
        if (secondsAgo == 0) {
            return (latest.price0Cumulative, latest.price1Cumulative);
        }
        return _cumulativeAt(latest.timestamp - secondsAgo, secondsAgo);
    }

    /// @notice Estimates mean absolute interval-to-interval price movement in ppm.
    /// @dev The estimate uses token1-per-token0 interval TWAPs within `secondsAgo`.
    function volatility(
        uint32 secondsAgo
    ) external view returns (uint256 volatilityPpm) {
        if (secondsAgo == 0) revert InvalidWindow();
        Observation memory latest = _latestOrRevert(secondsAgo);
        uint32 target = latest.timestamp - secondsAgo;
        (uint224 previousCumulative,) = _cumulativeAt(target, secondsAgo);
        uint32 previousTimestamp = target;
        uint256 previousPrice;
        uint256 totalMovement;
        uint256 samples;

        for (uint16 i; i < cardinality; ++i) {
            Observation memory current = observations[_chronologicalIndex(i)];
            if (current.timestamp <= target) continue;

            uint32 elapsed = current.timestamp - previousTimestamp;
            uint256 intervalPrice =
                uint256(_delta(current.price0Cumulative, previousCumulative)) / elapsed;
            if (previousPrice != 0 && intervalPrice != 0) {
                uint256 difference = intervalPrice > previousPrice
                    ? intervalPrice - previousPrice
                    : previousPrice - intervalPrice;
                uint256 movement = FullMath.mulDiv(difference, PPM, previousPrice);
                totalMovement += movement > PPM ? PPM : movement;
                ++samples;
            }
            if (intervalPrice != 0) previousPrice = intervalPrice;
            previousTimestamp = current.timestamp;
            previousCumulative = current.price0Cumulative;
        }
        volatilityPpm = samples == 0 ? 0 : totalMovement / samples;
    }

    /// @notice Returns running cumulatives including time since the latest pool update.
    function currentCumulativePrices()
        external
        view
        returns (uint32 timestamp, uint224 cumulative0, uint224 cumulative1)
    {
        timestamp = uint32(block.timestamp);
        cumulative0 = price0Cumulative;
        cumulative1 = price1Cumulative;
        if (!_initialized) return (timestamp, cumulative0, cumulative1);

        uint32 elapsed;
        unchecked {
            elapsed = timestamp - _lastUpdateTimestamp;
        }
        (uint224 price0X112, uint224 price1X112) = _spotPrices(_lastReserve0, _lastReserve1);
        unchecked {
            cumulative0 += uint224(uint256(price0X112) * elapsed);
            cumulative1 += uint224(uint256(price1X112) * elapsed);
        }
    }

    function _accumulate(
        uint32 timestamp
    ) internal {
        uint32 elapsed;
        unchecked {
            elapsed = timestamp - _lastUpdateTimestamp;
        }
        if (elapsed != 0) {
            (uint224 price0X112, uint224 price1X112) = _spotPrices(_lastReserve0, _lastReserve1);
            unchecked {
                price0Cumulative += uint224(uint256(price0X112) * elapsed);
                price1Cumulative += uint224(uint256(price1X112) * elapsed);
            }
            _lastUpdateTimestamp = timestamp;
        }
    }

    function _record(
        uint32 timestamp,
        uint224 cumulative0,
        uint224 cumulative1
    ) internal {
        uint16 index = observationIndex;
        observations[index] = Observation(timestamp, cumulative0, cumulative1);
        observationIndex = uint16((uint256(index) + 1) % OBSERVATION_CAPACITY);
        if (cardinality < OBSERVATION_CAPACITY) ++cardinality;
        emit ObservationRecorded(pool, index, timestamp, cumulative0, cumulative1);
    }

    function _cumulativeAt(
        uint32 target,
        uint32 requestedSecondsAgo
    ) internal view returns (uint224 cumulative0, uint224 cumulative1) {
        Observation memory beforeOrAt = observations[_chronologicalIndex(0)];
        if (target < beforeOrAt.timestamp) {
            Observation memory latest = _latest();
            revert InsufficientHistory(requestedSecondsAgo, latest.timestamp - beforeOrAt.timestamp);
        }

        for (uint16 i = 1; i < cardinality; ++i) {
            Observation memory afterOrAt = observations[_chronologicalIndex(i)];
            if (afterOrAt.timestamp < target) {
                beforeOrAt = afterOrAt;
                continue;
            }
            if (afterOrAt.timestamp == target) {
                return (afterOrAt.price0Cumulative, afterOrAt.price1Cumulative);
            }

            uint32 span = afterOrAt.timestamp - beforeOrAt.timestamp;
            uint32 offset = target - beforeOrAt.timestamp;
            unchecked {
                cumulative0 = beforeOrAt.price0Cumulative
                    + uint224(
                        FullMath.mulDiv(
                            _delta(afterOrAt.price0Cumulative, beforeOrAt.price0Cumulative),
                            offset,
                            span
                        )
                    );
                cumulative1 = beforeOrAt.price1Cumulative
                    + uint224(
                        FullMath.mulDiv(
                            _delta(afterOrAt.price1Cumulative, beforeOrAt.price1Cumulative),
                            offset,
                            span
                        )
                    );
            }
            return (cumulative0, cumulative1);
        }
        return (beforeOrAt.price0Cumulative, beforeOrAt.price1Cumulative);
    }

    function _spotPrices(
        uint112 reserve0,
        uint112 reserve1
    ) internal pure returns (uint224 price0X112, uint224 price1X112) {
        if (reserve0 == 0 || reserve1 == 0) return (0, 0);
        price0X112 = uint224(FullMath.mulDiv(reserve1, Q112, reserve0));
        price1X112 = uint224(FullMath.mulDiv(reserve0, Q112, reserve1));
    }

    function _latestOrRevert(
        uint32 requestedSecondsAgo
    ) internal view returns (Observation memory latest) {
        if (!_initialized) revert InsufficientHistory(requestedSecondsAgo, 0);
        latest = _latest();
        Observation memory oldest = observations[_chronologicalIndex(0)];
        uint32 available = latest.timestamp - oldest.timestamp;
        if (requestedSecondsAgo > available) {
            revert InsufficientHistory(requestedSecondsAgo, available);
        }
    }

    function _latest() internal view returns (Observation memory) {
        uint16 index = observationIndex == 0 ? OBSERVATION_CAPACITY - 1 : observationIndex - 1;
        return observations[index];
    }

    function _chronologicalIndex(
        uint16 offset
    ) internal view returns (uint16) {
        if (cardinality < OBSERVATION_CAPACITY) return offset;
        return uint16((uint256(observationIndex) + offset) % OBSERVATION_CAPACITY);
    }

    function _delta(
        uint224 later,
        uint224 earlier
    ) internal pure returns (uint224 difference) {
        unchecked {
            difference = later - earlier;
        }
    }
}
