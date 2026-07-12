// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import { IAuralisFactory } from "../interfaces/IAuralisFactory.sol";
import { IAuralisPool } from "../interfaces/IAuralisPool.sol";
import { IERC20Minimal } from "../interfaces/IERC20Minimal.sol";
import { FullMath } from "../libraries/FullMath.sol";
import {
    AuralisInvalidRoute,
    AuralisInvalidToken,
    AuralisUnknownPool
} from "../types/AuralisErrors.sol";
import {
    BurnQuote,
    FeePosition,
    MintQuote,
    PoolSnapshot,
    RiskStatus,
    RouteStep,
    SwapQuote
} from "../types/AuralisTypes.sol";

interface IAuralisPoolState {
    function imbalanceGuard() external view returns (address);
}

interface IAuralisRiskView {
    function evaluate(
        address pool,
        uint256 reserve0,
        uint256 reserve1
    ) external view returns (RiskStatus memory status);

    function anchorRatioX128(
        address pool
    ) external view returns (uint256 ratioX128);
}

contract AuralisPoolLens {
    uint256 private constant Q128 = 1 << 128;
    uint256 private constant PPM = 1_000_000;

    address public immutable factory;

    constructor(
        address factory_
    ) {
        if (factory_ == address(0) || factory_.code.length == 0) {
            revert AuralisUnknownPool(factory_);
        }
        factory = factory_;
    }

    function snapshot(
        address poolAddress
    ) public view returns (PoolSnapshot memory state) {
        IAuralisPool pool = _canonicalPool(poolAddress);
        (uint112 gross0, uint112 gross1,) = pool.getReserves();
        (uint112 active0, uint112 active1) = pool.activeReserves();
        (uint128 pending0, uint128 pending1) = pool.pendingLPFees();
        (uint128 protocol0, uint128 protocol1) = pool.protocolFees();
        RiskStatus memory risk = _evaluate(poolAddress, active0, active1);

        state.pool = poolAddress;
        state.token0 = pool.token0();
        state.token1 = pool.token1();
        state.grossReserve0 = gross0;
        state.grossReserve1 = gross1;
        state.activeReserve0 = active0;
        state.activeReserve1 = active1;
        state.pendingLPFee0 = pending0;
        state.pendingLPFee1 = pending1;
        state.protocolFee0 = protocol0;
        state.protocolFee1 = protocol1;
        state.totalSupply = IERC20Minimal(poolAddress).totalSupply();
        state.spotPrice0X128 = active0 == 0 ? 0 : FullMath.mulDiv(active1, Q128, active0);
        state.anchorRatioX128 = risk.initialized
            ? IAuralisRiskView(_guard(poolAddress)).anchorRatioX128(poolAddress)
            : 0;
        state.imbalancePpm = risk.imbalancePpm;
        state.blockTimestamp = block.timestamp;
        state.paused = pool.paused();
    }

    function feePosition(
        address poolAddress,
        address owner
    ) external view returns (FeePosition memory position) {
        IAuralisPool pool = _canonicalPool(poolAddress);
        (position.accrued0, position.accrued1) = pool.accruedFees(owner);
        (position.growthPaid0X128, position.growthPaid1X128) = pool.feeGrowthCheckpoint(owner);
        (uint256 global0, uint256 global1) = pool.feeGrowthGlobalX128();
        position.pendingGrowth0X128 = global0 - position.growthPaid0X128;
        position.pendingGrowth1X128 = global1 - position.growthPaid1X128;
    }

    function quoteMint(
        address poolAddress,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external view returns (MintQuote memory quote) {
        (quote.amount0, quote.amount1, quote.liquidity) =
            _canonicalPool(poolAddress).previewMint(amount0Desired, amount1Desired);
        quote.refund0 = amount0Desired - quote.amount0;
        quote.refund1 = amount1Desired - quote.amount1;
    }

    function quoteBurn(
        address poolAddress,
        address owner,
        uint256 liquidity
    ) external view returns (BurnQuote memory quote) {
        IAuralisPool pool = _canonicalPool(poolAddress);
        (quote.amount0, quote.amount1) = pool.previewBurn(owner, liquidity);
        if (liquidity == IERC20Minimal(poolAddress).balanceOf(owner)) {
            (uint112 active0, uint112 active1) = pool.activeReserves();
            uint256 supply = IERC20Minimal(poolAddress).totalSupply();
            quote.principal0 = FullMath.mulDiv(liquidity, active0, supply);
            quote.principal1 = FullMath.mulDiv(liquidity, active1, supply);
            if (quote.amount0 > quote.principal0) {
                quote.realizedFee0 = quote.amount0 - quote.principal0;
            }
            if (quote.amount1 > quote.principal1) {
                quote.realizedFee1 = quote.amount1 - quote.principal1;
            }
        } else {
            quote.principal0 = quote.amount0;
            quote.principal1 = quote.amount1;
        }
    }

    function quoteSwap(
        address poolAddress,
        address tokenIn,
        uint256 amountIn
    ) public view returns (SwapQuote memory quote) {
        IAuralisPool pool = _canonicalPool(poolAddress);
        address token0 = pool.token0();
        address token1 = pool.token1();
        bool zeroForOne;
        if (tokenIn == token0) zeroForOne = true;
        else if (tokenIn != token1) revert AuralisInvalidToken(tokenIn);

        quote.tokenIn = tokenIn;
        quote.tokenOut = zeroForOne ? token1 : token0;
        quote.amountIn = amountIn;
        (quote.amountOut, quote.lpFee, quote.protocolFee) = pool.quoteExactInput(tokenIn, amountIn);
        quote.netAmountIn = amountIn - quote.lpFee - quote.protocolFee;
        (uint112 active0, uint112 active1) = pool.activeReserves();
        quote.projectedReserve0 =
            zeroForOne ? uint256(active0) + quote.netAmountIn : active0 - quote.amountOut;
        quote.projectedReserve1 =
            zeroForOne ? active1 - quote.amountOut : uint256(active1) + quote.netAmountIn;
        quote.feePpm = uint24(FullMath.mulDiv(quote.lpFee + quote.protocolFee, PPM, amountIn));
        RiskStatus memory projected =
            _evaluate(poolAddress, quote.projectedReserve0, quote.projectedReserve1);
        quote.projectedImbalancePpm = projected.imbalancePpm;
    }

    function quoteRoute(
        RouteStep[] calldata route,
        address tokenIn,
        uint256 amountIn
    ) external view returns (SwapQuote[] memory quotes, uint256 amountOut) {
        uint256 length = route.length;
        if (length == 0) revert AuralisInvalidRoute(0);
        quotes = new SwapQuote[](length);
        address currentToken = tokenIn;
        amountOut = amountIn;
        for (uint256 i; i < length; ++i) {
            quotes[i] = quoteSwap(route[i].pool, currentToken, amountOut);
            if (quotes[i].tokenOut != route[i].tokenOut) revert AuralisInvalidRoute(i);
            currentToken = route[i].tokenOut;
            amountOut = quotes[i].amountOut;
        }
    }

    function riskStatus(
        address poolAddress
    ) external view returns (RiskStatus memory status) {
        IAuralisPool pool = _canonicalPool(poolAddress);
        (uint112 reserve0, uint112 reserve1) = pool.activeReserves();
        return _evaluate(poolAddress, reserve0, reserve1);
    }

    function _evaluate(
        address pool,
        uint256 reserve0,
        uint256 reserve1
    ) internal view returns (RiskStatus memory) {
        return IAuralisRiskView(_guard(pool)).evaluate(pool, reserve0, reserve1);
    }

    function _guard(
        address pool
    ) internal view returns (address) {
        return IAuralisPoolState(pool).imbalanceGuard();
    }

    function _canonicalPool(
        address poolAddress
    ) internal view returns (IAuralisPool pool) {
        if (poolAddress == address(0) || poolAddress.code.length == 0) {
            revert AuralisUnknownPool(poolAddress);
        }
        pool = IAuralisPool(poolAddress);
        address token0 = pool.token0();
        address token1 = pool.token1();
        if (
            pool.factory() != factory
                || IAuralisFactory(factory).getPool(token0, token1) != poolAddress
        ) revert AuralisUnknownPool(poolAddress);
    }
}
