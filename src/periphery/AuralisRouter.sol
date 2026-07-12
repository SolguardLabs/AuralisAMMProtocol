// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import { IAuralisFactory } from "../interfaces/IAuralisFactory.sol";
import { IAuralisPool } from "../interfaces/IAuralisPool.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import {
    AuralisDeadlineExpired,
    AuralisInsufficientShares,
    AuralisInvalidRoute,
    AuralisInvalidToken,
    AuralisNativeTransferRejected,
    AuralisUnknownPool,
    AuralisUnsupportedToken,
    AuralisZeroAddress,
    AuralisZeroAmount
} from "../types/AuralisErrors.sol";
import { RouteStep, SwapRequest } from "../types/AuralisTypes.sol";
import { ReentrancyGuard } from "../utils/ReentrancyGuard.sol";

interface IAuralisPoolPermit {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

contract AuralisRouter is ReentrancyGuard {
    using SafeTransferLib for address;

    struct AddLiquidityParams {
        address pool;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Minimum;
        uint256 amount1Minimum;
        uint256 liquidityMinimum;
        address recipient;
        uint256 deadline;
    }

    struct RemoveLiquidityParams {
        address pool;
        uint256 liquidity;
        uint256 amount0Minimum;
        uint256 amount1Minimum;
        address recipient;
        uint256 deadline;
    }

    struct PermitParams {
        bool approveMaximum;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    struct RouteExecution {
        address token;
        uint256 amount;
        uint256 minimum;
        address recipient;
        uint256 deadline;
    }

    address public immutable factory;

    constructor(
        address factory_
    ) {
        if (factory_ == address(0) || factory_.code.length == 0) revert AuralisZeroAddress();
        factory = factory_;
    }

    function addLiquidity(
        AddLiquidityParams calldata params
    ) external nonReentrant returns (uint256 amount0, uint256 amount1, uint256 liquidity) {
        _requireDeadline(params.deadline);
        _requireRecipient(params.recipient);
        if (params.amount0Desired == 0 || params.amount1Desired == 0) {
            revert AuralisZeroAmount();
        }

        (IAuralisPool pool, address token0, address token1) = _canonicalPool(params.pool);
        _pullExact(token0, msg.sender, params.amount0Desired);
        _pullExact(token1, msg.sender, params.amount1Desired);
        token0.forceApprove(params.pool, params.amount0Desired);
        token1.forceApprove(params.pool, params.amount1Desired);

        (amount0, amount1, liquidity) = pool.mint(
            params.recipient,
            params.amount0Desired,
            params.amount1Desired,
            params.amount0Minimum,
            params.amount1Minimum,
            params.deadline
        );
        if (liquidity < params.liquidityMinimum) {
            revert AuralisInsufficientShares(params.liquidityMinimum, liquidity);
        }
        token0.forceApprove(params.pool, 0);
        token1.forceApprove(params.pool, 0);

        if (params.amount0Desired != amount0) {
            token0.safeTransfer(msg.sender, params.amount0Desired - amount0);
        }
        if (params.amount1Desired != amount1) {
            token1.safeTransfer(msg.sender, params.amount1Desired - amount1);
        }
    }

    function removeLiquidity(
        RemoveLiquidityParams calldata params
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        return _removeLiquidity(params);
    }

    function removeLiquidityWithPermit(
        RemoveLiquidityParams calldata params,
        PermitParams calldata permitParams
    ) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        _requireDeadline(params.deadline);
        _canonicalPool(params.pool);
        uint256 value = permitParams.approveMaximum ? type(uint256).max : params.liquidity;
        IAuralisPoolPermit(params.pool)
            .permit(
                msg.sender,
                address(this),
                value,
                permitParams.deadline,
                permitParams.v,
                permitParams.r,
                permitParams.s
            );
        return _removeLiquidity(params);
    }

    function swapExactInputSingle(
        SwapRequest calldata request
    ) external nonReentrant returns (uint256 amountOut) {
        _requireDeadline(request.deadline);
        _requireRecipient(request.recipient);
        if (request.amountIn == 0) revert AuralisZeroAmount();

        (IAuralisPool pool, address token0, address token1) = _canonicalPool(request.pool);
        _tokenOut(token0, token1, request.tokenIn, 0);
        _pullExact(request.tokenIn, msg.sender, request.amountIn);
        request.tokenIn.forceApprove(request.pool, request.amountIn);
        amountOut = pool.swapExactInput(
            request.tokenIn,
            request.amountIn,
            request.minimumAmountOut,
            request.recipient,
            request.deadline
        );
        request.tokenIn.forceApprove(request.pool, 0);
    }

    function swapExactInput(
        RouteStep[] calldata route,
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address recipient,
        uint256 deadline
    ) external nonReentrant returns (uint256 amountOut) {
        _requireDeadline(deadline);
        _requireRecipient(recipient);
        if (amountIn == 0) revert AuralisZeroAmount();
        _validateRoute(route, tokenIn);
        _pullExact(tokenIn, msg.sender, amountIn);
        RouteExecution memory execution = RouteExecution({
            token: tokenIn,
            amount: amountIn,
            minimum: amountOutMinimum,
            recipient: recipient,
            deadline: deadline
        });
        amountOut = _executeRoute(route, execution);
    }

    function _validateRoute(
        RouteStep[] calldata route,
        address tokenIn
    ) internal view returns (address currentToken) {
        uint256 length = route.length;
        if (length == 0) revert AuralisInvalidRoute(0);
        currentToken = tokenIn;
        for (uint256 i; i < length; ++i) {
            (, address token0, address token1) = _canonicalPool(route[i].pool);
            if (_tokenOut(token0, token1, currentToken, i) != route[i].tokenOut) {
                revert AuralisInvalidRoute(i);
            }
            currentToken = route[i].tokenOut;
        }
    }

    function _executeRoute(
        RouteStep[] calldata route,
        RouteExecution memory execution
    ) internal returns (uint256) {
        uint256 length = route.length;
        for (uint256 i; i < length; ++i) {
            bool last = i + 1 == length;
            execution.amount = _executeStep(route[i], execution, last);
            execution.token = route[i].tokenOut;
        }
        return execution.amount;
    }

    function _executeStep(
        RouteStep calldata step,
        RouteExecution memory execution,
        bool last
    ) internal returns (uint256 amountOut) {
        address stepRecipient = last ? execution.recipient : address(this);
        execution.token.forceApprove(step.pool, execution.amount);
        uint256 balanceBefore = last ? 0 : step.tokenOut.safeBalanceOf(address(this));
        amountOut = IAuralisPool(step.pool)
            .swapExactInput(
                execution.token,
                execution.amount,
                last ? execution.minimum : 0,
                stepRecipient,
                execution.deadline
            );
        execution.token.forceApprove(step.pool, 0);
        if (!last) {
            uint256 balanceAfter = step.tokenOut.safeBalanceOf(address(this));
            uint256 received = balanceAfter >= balanceBefore ? balanceAfter - balanceBefore : 0;
            if (received != amountOut) {
                revert AuralisUnsupportedToken(step.tokenOut, amountOut, received);
            }
        }
    }

    function _removeLiquidity(
        RemoveLiquidityParams calldata params
    ) internal returns (uint256 amount0, uint256 amount1) {
        _requireDeadline(params.deadline);
        _requireRecipient(params.recipient);
        if (params.liquidity == 0) revert AuralisZeroAmount();
        (IAuralisPool pool,,) = _canonicalPool(params.pool);
        (amount0, amount1) = pool.burn(
            msg.sender,
            params.recipient,
            params.liquidity,
            params.amount0Minimum,
            params.amount1Minimum,
            params.deadline
        );
    }

    function _canonicalPool(
        address poolAddress
    ) internal view returns (IAuralisPool pool, address token0, address token1) {
        if (poolAddress == address(0) || poolAddress.code.length == 0) {
            revert AuralisUnknownPool(poolAddress);
        }
        pool = IAuralisPool(poolAddress);
        token0 = pool.token0();
        token1 = pool.token1();
        if (
            pool.factory() != factory
                || IAuralisFactory(factory).getPool(token0, token1) != poolAddress
        ) revert AuralisUnknownPool(poolAddress);
    }

    function _tokenOut(
        address token0,
        address token1,
        address tokenIn,
        uint256 step
    ) internal pure returns (address) {
        if (tokenIn == token0) return token1;
        if (tokenIn == token1) return token0;
        if (step == 0) revert AuralisInvalidToken(tokenIn);
        revert AuralisInvalidRoute(step);
    }

    function _pullExact(
        address token,
        address owner,
        uint256 amount
    ) internal {
        uint256 balanceBefore = token.safeBalanceOf(address(this));
        token.safeTransferFrom(owner, address(this), amount);
        uint256 balanceAfter = token.safeBalanceOf(address(this));
        uint256 received = balanceAfter >= balanceBefore ? balanceAfter - balanceBefore : 0;
        if (received != amount) revert AuralisUnsupportedToken(token, amount, received);
    }

    function _requireRecipient(
        address recipient
    ) internal pure {
        if (recipient == address(0)) revert AuralisZeroAddress();
    }

    function _requireDeadline(
        uint256 deadline
    ) internal view {
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > deadline) revert AuralisDeadlineExpired(deadline, block.timestamp);
    }

    receive() external payable {
        revert AuralisNativeTransferRejected();
    }
}
