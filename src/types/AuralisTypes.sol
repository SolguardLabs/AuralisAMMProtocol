// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Complete accounting view for a pool at one block.
struct PoolSnapshot {
    address pool;
    address token0;
    address token1;
    uint256 grossReserve0;
    uint256 grossReserve1;
    uint256 activeReserve0;
    uint256 activeReserve1;
    uint256 pendingLPFee0;
    uint256 pendingLPFee1;
    uint256 protocolFee0;
    uint256 protocolFee1;
    uint256 totalSupply;
    uint256 spotPrice0X128;
    uint256 anchorRatioX128;
    uint256 imbalancePpm;
    uint256 blockTimestamp;
    bool paused;
}

/// @notice Fee policy components returned for an exact-input quote.
struct FeeQuote {
    uint24 totalFeePpm;
    uint24 protocolSharePpm;
    uint24 baseFeePpm;
    uint24 sizeSurchargePpm;
    uint24 imbalanceSurchargePpm;
    uint24 volatilitySurchargePpm;
}

/// @notice Amounts and shares projected for a liquidity contribution.
struct MintQuote {
    uint256 amount0;
    uint256 amount1;
    uint256 liquidity;
    uint256 refund0;
    uint256 refund1;
}

/// @notice Asset amounts projected for a liquidity redemption.
struct BurnQuote {
    uint256 amount0;
    uint256 amount1;
    uint256 principal0;
    uint256 principal1;
    uint256 realizedFee0;
    uint256 realizedFee1;
}

/// @notice Current fee entitlement for one share holder.
struct FeePosition {
    uint256 accrued0;
    uint256 accrued1;
    uint256 growthPaid0X128;
    uint256 growthPaid1X128;
    uint256 pendingGrowth0X128;
    uint256 pendingGrowth1X128;
}

/// @notice Inputs used to inspect a prospective swap.
struct SwapRequest {
    address pool;
    address tokenIn;
    uint256 amountIn;
    uint256 minimumAmountOut;
    address recipient;
    uint256 deadline;
}

/// @notice Result of a prospective exact-input swap.
struct SwapQuote {
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint256 netAmountIn;
    uint256 amountOut;
    uint256 lpFee;
    uint256 protocolFee;
    uint24 feePpm;
    uint256 projectedReserve0;
    uint256 projectedReserve1;
    uint256 projectedImbalancePpm;
}

/// @notice A single pool transition in a routed swap.
struct RouteStep {
    address pool;
    address tokenOut;
}

/// @notice Result of the risk controller for a reserve pair.
struct RiskStatus {
    uint256 normalizedReserve0;
    uint256 normalizedReserve1;
    uint256 imbalancePpm;
    uint256 minimumReserve;
    uint24 maximumImbalancePpm;
    bool initialized;
    bool accepted;
}

/// @notice Parameters supplied when a pool receives its initial policy.
struct PoolRiskConfig {
    uint24 maximumImbalancePpm;
    uint112 minimumActiveReserve;
}

/// @notice Per-pool overrides used by the adaptive fee controller.
struct PoolFeeConfig {
    uint24 baseFeePpm;
    uint24 minimumFeePpm;
    uint24 maximumFeePpm;
    uint24 sizeSlopePpm;
    uint24 imbalanceSlopePpm;
    uint24 volatilitySlopePpm;
    bool enabled;
}

/// @title Auralis numeric constants
/// @notice Shared denominators and fixed-point units used by views and periphery contracts.
library AuralisConstants {
    uint256 internal constant PPM = 1_000_000;
    uint256 internal constant BPS = 10_000;
    uint256 internal constant Q96 = 1 << 96;
    uint256 internal constant Q128 = 1 << 128;
    uint256 internal constant MINIMUM_LIQUIDITY = 1000;
    address internal constant MINIMUM_LIQUIDITY_HOLDER =
        address(0x000000000000000000000000000000000000dEaD);
}

