// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IAuralisFactory } from "../interfaces/IAuralisFactory.sol";
import { IAuralisFeeController } from "../interfaces/IAuralisFeeController.sol";
import { IAuralisOracle } from "../interfaces/IAuralisOracle.sol";
import { IAuralisPool } from "../interfaces/IAuralisPool.sol";
import { AuralisMath } from "../libraries/AuralisMath.sol";
import { FullMath } from "../libraries/FullMath.sol";
import { LiquiditySettlement } from "../libraries/LiquiditySettlement.sol";
import { ReserveMath } from "../libraries/ReserveMath.sol";
import { SafeTransferLib } from "../libraries/SafeTransferLib.sol";
import { AuralisLPToken } from "../tokens/AuralisLPToken.sol";
import {
    AuralisAccountingDeficit,
    AuralisAmount0BelowMinimum,
    AuralisAmount1BelowMinimum,
    AuralisDeadlineExpired,
    AuralisInsufficientLiquidity,
    AuralisInvalidConfiguration,
    AuralisInvalidToken,
    AuralisOutputBelowMinimum,
    AuralisPoolNotInitialized,
    AuralisPoolPaused,
    AuralisUnauthorized,
    AuralisUnsupportedToken,
    AuralisZeroAddress,
    AuralisZeroAmount
} from "../types/AuralisErrors.sol";
import { AuralisConstants, BurnQuote, PoolRiskConfig } from "../types/AuralisTypes.sol";
import { ReentrancyGuard } from "../utils/ReentrancyGuard.sol";

/// @dev Risk-controller surface consumed by individual pools.
interface IAuralisImbalanceGuard {
    function initializePool(
        address pool,
        uint256 reserve0,
        uint256 reserve1
    ) external;

    function checkVirtualReserves(
        address pool,
        uint256 reserve0,
        uint256 reserve1
    ) external view returns (uint256 imbalancePpm);

    function riskConfig(
        address pool
    ) external view returns (PoolRiskConfig memory configuration);
}

/// @title Auralis constant-product pool
/// @notice Two-token AMM with adaptive fees, LP fee checkpoints and bounded reserve composition.
contract AuralisPool is IAuralisPool, AuralisLPToken, ReentrancyGuard {
    using SafeTransferLib for address;

    uint256 private constant Q128 = 1 << 128;
    uint24 private constant DEFAULT_FEE_PPM = 3000;

    /// @notice Emitted after the oracle used by the pool is attached or replaced.
    event OracleUpdated(address indexed previousOracle, address indexed newOracle);

    /// @notice Emitted when global fee growth advances for either token.
    event FeeGrowthUpdated(
        uint256 feeGrowth0X128, uint256 feeGrowth1X128, uint128 pendingFee0, uint128 pendingFee1
    );

    /// @inheritdoc IAuralisPool
    address public immutable override factory;

    /// @inheritdoc IAuralisPool
    address public immutable override token0;

    /// @inheritdoc IAuralisPool
    address public immutable override token1;

    /// @notice Controller that validates the active-reserve composition.
    address public immutable imbalanceGuard;

    /// @inheritdoc IAuralisPool
    address public override oracle;

    /// @inheritdoc IAuralisPool
    bool public override paused;

    uint112 private _reserve0;
    uint112 private _reserve1;
    uint32 private _blockTimestampLast;

    uint128 private _pendingLPFee0;
    uint128 private _pendingLPFee1;
    uint128 private _protocolFee0;
    uint128 private _protocolFee1;

    uint256 private _feeGrowthGlobal0X128;
    uint256 private _feeGrowthGlobal1X128;

    mapping(address account => uint256 growth) private _feeGrowthCheckpoint0X128;
    mapping(address account => uint256 growth) private _feeGrowthCheckpoint1X128;
    mapping(address account => uint256 amount) private _feesOwed0;
    mapping(address account => uint256 amount) private _feesOwed1;

    /// @param factory_ Canonical factory responsible for this pool.
    /// @param token0_ Lower-address pool token.
    /// @param token1_ Higher-address pool token.
    /// @param imbalanceGuard_ Reserve-composition policy shared by factory pools.
    constructor(
        address factory_,
        address token0_,
        address token1_,
        address imbalanceGuard_
    ) AuralisLPToken("Auralis LP Share", "AURA-LP") {
        if (
            factory_ == address(0) || token0_ == address(0) || token1_ == address(0)
                || imbalanceGuard_ == address(0)
        ) revert AuralisZeroAddress();
        if (token0_ >= token1_) revert AuralisInvalidConfiguration();
        if (token0_.code.length == 0 || token1_.code.length == 0) {
            revert AuralisInvalidConfiguration();
        }

        factory = factory_;
        token0 = token0_;
        token1 = token1_;
        imbalanceGuard = imbalanceGuard_;
    }

    /// @notice Rejects direct native-currency transfers.
    receive() external payable {
        revert AuralisInvalidToken(address(0));
    }

    /// @inheritdoc IAuralisPool
    function maxImbalancePpm() external view override returns (uint24 maximum) {
        maximum = _riskConfiguration().maximumImbalancePpm;
    }

    /// @inheritdoc IAuralisPool
    function minimumReserve() external view override returns (uint112 minimum) {
        minimum = _riskConfiguration().minimumActiveReserve;
    }

    /// @inheritdoc IAuralisPool
    function getReserves()
        external
        view
        override
        returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast)
    {
        return (_reserve0, _reserve1, _blockTimestampLast);
    }

    /// @inheritdoc IAuralisPool
    function activeReserves() public view override returns (uint112 reserve0, uint112 reserve1) {
        return ReserveMath.activeReserves(_reserve0, _reserve1, _feeBalances());
    }

    /// @inheritdoc IAuralisPool
    function pendingLPFees() external view override returns (uint128 fee0, uint128 fee1) {
        return (_pendingLPFee0, _pendingLPFee1);
    }

    /// @inheritdoc IAuralisPool
    function protocolFees() external view override returns (uint128 fee0, uint128 fee1) {
        return (_protocolFee0, _protocolFee1);
    }

    /// @inheritdoc IAuralisPool
    function feeGrowthGlobalX128()
        external
        view
        override
        returns (uint256 growth0, uint256 growth1)
    {
        return (_feeGrowthGlobal0X128, _feeGrowthGlobal1X128);
    }

    /// @inheritdoc IAuralisPool
    function feeGrowthCheckpoint(
        address owner
    ) external view override returns (uint256 growth0, uint256 growth1) {
        return (_feeGrowthCheckpoint0X128[owner], _feeGrowthCheckpoint1X128[owner]);
    }

    /// @inheritdoc IAuralisPool
    function accruedFees(
        address owner
    ) public view override returns (uint256 amount0, uint256 amount1) {
        amount0 = _feesOwed0[owner];
        amount1 = _feesOwed1[owner];

        uint256 holderBalance = balanceOf[owner];
        if (holderBalance == 0) return (amount0, amount1);

        uint256 growthDelta0 = _feeGrowthGlobal0X128 - _feeGrowthCheckpoint0X128[owner];
        uint256 growthDelta1 = _feeGrowthGlobal1X128 - _feeGrowthCheckpoint1X128[owner];
        if (growthDelta0 != 0) {
            amount0 += FullMath.mulDiv(holderBalance, growthDelta0, Q128);
        }
        if (growthDelta1 != 0) {
            amount1 += FullMath.mulDiv(holderBalance, growthDelta1, Q128);
        }
    }

    /// @inheritdoc IAuralisPool
    function previewMint(
        uint256 amount0Desired,
        uint256 amount1Desired
    ) public view override returns (uint256 amount0, uint256 amount1, uint256 liquidity) {
        if (amount0Desired == 0 || amount1Desired == 0) revert AuralisZeroAmount();

        uint256 supply = totalSupply;
        if (supply == 0) {
            amount0 = amount0Desired;
            amount1 = amount1Desired;
            liquidity = AuralisMath.initialLiquidity(amount0, amount1);
            return (amount0, amount1, liquidity);
        }

        (uint112 active0, uint112 active1) = activeReserves();
        if (active0 == 0 || active1 == 0) revert AuralisInsufficientLiquidity();

        uint256 amount1Optimal = FullMath.mulDiv(amount0Desired, active1, active0);
        if (amount1Optimal <= amount1Desired) {
            amount0 = amount0Desired;
            amount1 = amount1Optimal;
        } else {
            amount0 = FullMath.mulDiv(amount1Desired, active0, active1);
            amount1 = amount1Desired;
        }
        liquidity = AuralisMath.liquidityForAmounts(amount0, amount1, active0, active1, supply);
        if (liquidity == 0) revert AuralisInsufficientLiquidity();
    }

    /// @inheritdoc IAuralisPool
    function previewBurn(
        address owner,
        uint256 liquidity
    ) public view override returns (uint256 amount0, uint256 amount1) {
        BurnQuote memory quote = previewBurnBreakdown(owner, liquidity);
        return (quote.amount0, quote.amount1);
    }

    /// @inheritdoc IAuralisPool
    function previewBurnBreakdown(
        address owner,
        uint256 liquidity
    ) public view override returns (BurnQuote memory quote) {
        if (owner == address(0)) revert AuralisZeroAddress();
        if (liquidity == 0 || liquidity > balanceOf[owner]) {
            revert AuralisInsufficientLiquidity();
        }
        quote = _redemptionQuote(owner, liquidity);
    }

    /// @inheritdoc IAuralisPool
    function mint(
        address recipient,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Minimum,
        uint256 amount1Minimum,
        uint256 deadline
    ) external override nonReentrant returns (uint256 amount0, uint256 amount1, uint256 liquidity) {
        _requireDeadline(deadline);
        _requireOperational();
        if (recipient == address(0)) revert AuralisZeroAddress();

        (amount0, amount1, liquidity) = previewMint(amount0Desired, amount1Desired);
        if (amount0 < amount0Minimum) {
            revert AuralisAmount0BelowMinimum(amount0Minimum, amount0);
        }
        if (amount1 < amount1Minimum) {
            revert AuralisAmount1BelowMinimum(amount1Minimum, amount1);
        }

        _pullExact(token0, msg.sender, amount0);
        _pullExact(token1, msg.sender, amount1);

        bool initialMint = totalSupply == 0;
        if (initialMint) {
            _mint(AuralisConstants.MINIMUM_LIQUIDITY_HOLDER, AuralisConstants.MINIMUM_LIQUIDITY);
        }
        _mint(recipient, liquidity);

        uint256 balance0 = token0.safeBalanceOf(address(this));
        uint256 balance1 = token1.safeBalanceOf(address(this));
        if (initialMint) {
            IAuralisImbalanceGuard(imbalanceGuard).initializePool(address(this), balance0, balance1);
        }
        _writeReserves(balance0, balance1, true);

        emit Mint(msg.sender, recipient, amount0, amount1, liquidity);
    }

    /// @inheritdoc IAuralisPool
    function burn(
        address owner,
        address recipient,
        uint256 liquidity,
        uint256 amount0Minimum,
        uint256 amount1Minimum,
        uint256 deadline
    ) external override nonReentrant returns (uint256 amount0, uint256 amount1) {
        _requireDeadline(deadline);
        if (owner == address(0) || recipient == address(0)) revert AuralisZeroAddress();
        if (liquidity == 0 || liquidity > balanceOf[owner]) {
            revert AuralisInsufficientLiquidity();
        }
        if (msg.sender != owner) _spendAllowance(owner, msg.sender, liquidity);

        _accrueAccount(owner);
        BurnQuote memory quote = _redemptionQuote(owner, liquidity);
        amount0 = quote.amount0;
        amount1 = quote.amount1;
        if (amount0 < amount0Minimum) {
            revert AuralisAmount0BelowMinimum(amount0Minimum, amount0);
        }
        if (amount1 < amount1Minimum) {
            revert AuralisAmount1BelowMinimum(amount1Minimum, amount1);
        }

        if (quote.realizedFee0 != 0 || quote.realizedFee1 != 0) {
            _realizeAccountFees(owner, quote.realizedFee0, quote.realizedFee1);
        }

        _burn(owner, liquidity);
        token0.safeTransfer(recipient, amount0);
        token1.safeTransfer(recipient, amount1);
        _writeReserves(
            token0.safeBalanceOf(address(this)), token1.safeBalanceOf(address(this)), true
        );

        emit Burn(owner, recipient, amount0, amount1, liquidity);
    }

    /// @inheritdoc IAuralisPool
    function quoteExactInput(
        address tokenIn,
        uint256 amountIn
    ) public view override returns (uint256 amountOut, uint256 lpFee, uint256 protocolFee) {
        if (amountIn == 0) revert AuralisZeroAmount();
        if (totalSupply <= AuralisConstants.MINIMUM_LIQUIDITY) {
            revert AuralisPoolNotInitialized();
        }

        bool zeroForOne = _zeroForOne(tokenIn);
        (uint112 active0, uint112 active1) = activeReserves();
        uint256 reserveIn = zeroForOne ? active0 : active1;
        uint256 reserveOut = zeroForOne ? active1 : active0;

        (uint24 feePpm, uint24 protocolSharePpm) =
            _feeQuote(zeroForOne, amountIn, reserveIn, reserveOut);
        uint256 netAmountIn;
        (netAmountIn, lpFee, protocolFee) = AuralisMath.splitFee(amountIn, feePpm, protocolSharePpm);
        amountOut = ReserveMath.amountOut(netAmountIn, reserveIn, reserveOut);

        uint256 projected0 = zeroForOne ? uint256(active0) + netAmountIn : active0 - amountOut;
        uint256 projected1 = zeroForOne ? active1 - amountOut : uint256(active1) + netAmountIn;
        _checkComposition(projected0, projected1);
    }

    /// @inheritdoc IAuralisPool
    function swapExactInput(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMinimum,
        address recipient,
        uint256 deadline
    ) external override nonReentrant returns (uint256 amountOut) {
        _requireDeadline(deadline);
        _requireOperational();
        if (recipient == address(0)) revert AuralisZeroAddress();

        bool zeroForOne = _zeroForOne(tokenIn);
        uint256 lpFee;
        uint256 protocolFee;
        (amountOut, lpFee, protocolFee) = quoteExactInput(tokenIn, amountIn);
        if (amountOut < amountOutMinimum) {
            revert AuralisOutputBelowMinimum(amountOutMinimum, amountOut);
        }

        _pullExact(tokenIn, msg.sender, amountIn);
        _recordSwapFees(zeroForOne, lpFee, protocolFee);

        address tokenOut = zeroForOne ? token1 : token0;
        tokenOut.safeTransfer(recipient, amountOut);
        _writeReserves(
            token0.safeBalanceOf(address(this)), token1.safeBalanceOf(address(this)), true
        );

        emit Swap(msg.sender, recipient, tokenIn, amountIn, amountOut, lpFee, protocolFee);
    }

    /// @inheritdoc IAuralisPool
    function claimFees(
        address recipient
    ) external override nonReentrant returns (uint256 amount0, uint256 amount1) {
        if (recipient == address(0)) revert AuralisZeroAddress();
        _accrueAccount(msg.sender);

        amount0 = AuralisMath.min(_feesOwed0[msg.sender], _pendingLPFee0);
        amount1 = AuralisMath.min(_feesOwed1[msg.sender], _pendingLPFee1);
        _realizeAccountFees(msg.sender, amount0, amount1);

        if (amount0 != 0) token0.safeTransfer(recipient, amount0);
        if (amount1 != 0) token1.safeTransfer(recipient, amount1);
        _writeReserves(
            token0.safeBalanceOf(address(this)), token1.safeBalanceOf(address(this)), false
        );

        emit FeesClaimed(msg.sender, recipient, amount0, amount1);
    }

    /// @inheritdoc IAuralisPool
    function collectProtocolFees()
        external
        override
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        address recipient = IAuralisFactory(factory).protocolFeeRecipient();
        if (recipient == address(0)) revert AuralisZeroAddress();

        amount0 = _protocolFee0;
        amount1 = _protocolFee1;
        _protocolFee0 = 0;
        _protocolFee1 = 0;

        if (amount0 != 0) token0.safeTransfer(recipient, amount0);
        if (amount1 != 0) token1.safeTransfer(recipient, amount1);
        _writeReserves(
            token0.safeBalanceOf(address(this)), token1.safeBalanceOf(address(this)), false
        );

        emit ProtocolFeesCollected(recipient, amount0, amount1);
    }

    /// @inheritdoc IAuralisPool
    function skim(
        address recipient
    ) external override nonReentrant {
        if (recipient == address(0)) revert AuralisZeroAddress();
        uint256 balance0 = token0.safeBalanceOf(address(this));
        uint256 balance1 = token1.safeBalanceOf(address(this));

        if (balance0 > _reserve0) token0.safeTransfer(recipient, balance0 - _reserve0);
        if (balance1 > _reserve1) token1.safeTransfer(recipient, balance1 - _reserve1);
    }

    /// @inheritdoc IAuralisPool
    function sync() external override nonReentrant {
        if (totalSupply == 0) revert AuralisPoolNotInitialized();
        _writeReserves(
            token0.safeBalanceOf(address(this)), token1.safeBalanceOf(address(this)), true
        );
    }

    /// @inheritdoc IAuralisPool
    function setPaused(
        bool newPaused
    ) external override {
        if (msg.sender != factory) revert AuralisUnauthorized(msg.sender);
        paused = newPaused;
        emit PauseStateUpdated(newPaused);
    }

    /// @notice Attaches a pool-specific oracle maintained by the factory.
    function setOracle(
        address newOracle
    ) external {
        if (msg.sender != factory) revert AuralisUnauthorized(msg.sender);
        if (newOracle != address(0) && IAuralisOracle(newOracle).pool() != address(this)) {
            revert AuralisInvalidConfiguration();
        }

        address previousOracle = oracle;
        oracle = newOracle;
        emit OracleUpdated(previousOracle, newOracle);

        if (newOracle != address(0) && totalSupply != 0) {
            (uint112 active0, uint112 active1) = activeReserves();
            IAuralisOracle(newOracle).update(active0, active1);
        }
    }

    /// @notice Returns the sum of tracked obligations for each pool asset.
    function accountedObligations()
        external
        view
        returns (uint256 obligation0, uint256 obligation1)
    {
        obligation0 = uint256(_pendingLPFee0) + _protocolFee0;
        obligation1 = uint256(_pendingLPFee1) + _protocolFee1;
    }

    /// @notice Returns the supply that participates in LP fee distribution.
    function feeBearingSupply() public view returns (uint256 supply) {
        uint256 currentSupply = totalSupply;
        if (currentSupply > AuralisConstants.MINIMUM_LIQUIDITY) {
            supply = currentSupply - AuralisConstants.MINIMUM_LIQUIDITY;
        }
    }

    function _recordSwapFees(
        bool zeroForOne,
        uint256 lpFee,
        uint256 protocolFee
    ) internal {
        uint256 supply = feeBearingSupply();
        if (supply == 0) revert AuralisPoolNotInitialized();

        if (zeroForOne) {
            _pendingLPFee0 = AuralisMath.toUint128(uint256(_pendingLPFee0) + lpFee);
            _protocolFee0 = AuralisMath.toUint128(uint256(_protocolFee0) + protocolFee);
            if (lpFee != 0) {
                _feeGrowthGlobal0X128 += FullMath.mulDiv(lpFee, Q128, supply);
            }
        } else {
            _pendingLPFee1 = AuralisMath.toUint128(uint256(_pendingLPFee1) + lpFee);
            _protocolFee1 = AuralisMath.toUint128(uint256(_protocolFee1) + protocolFee);
            if (lpFee != 0) {
                _feeGrowthGlobal1X128 += FullMath.mulDiv(lpFee, Q128, supply);
            }
        }

        emit FeeGrowthUpdated(
            _feeGrowthGlobal0X128, _feeGrowthGlobal1X128, _pendingLPFee0, _pendingLPFee1
        );
    }

    function _accrueAccount(
        address account
    ) internal {
        if (account == address(0) || account == AuralisConstants.MINIMUM_LIQUIDITY_HOLDER) {
            return;
        }

        uint256 accountBalance = balanceOf[account];
        uint256 checkpoint0 = _feeGrowthCheckpoint0X128[account];
        uint256 checkpoint1 = _feeGrowthCheckpoint1X128[account];
        if (accountBalance != 0) {
            uint256 delta0 = _feeGrowthGlobal0X128 - checkpoint0;
            uint256 delta1 = _feeGrowthGlobal1X128 - checkpoint1;
            if (delta0 != 0) {
                _feesOwed0[account] += FullMath.mulDiv(accountBalance, delta0, Q128);
            }
            if (delta1 != 0) {
                _feesOwed1[account] += FullMath.mulDiv(accountBalance, delta1, Q128);
            }
        }

        _feeGrowthCheckpoint0X128[account] = _feeGrowthGlobal0X128;
        _feeGrowthCheckpoint1X128[account] = _feeGrowthGlobal1X128;
    }

    function _realizeAccountFees(
        address owner,
        uint256 amount0,
        uint256 amount1
    ) internal {
        if (amount0 > _feesOwed0[owner] || amount0 > _pendingLPFee0) {
            revert AuralisAccountingDeficit(token0, _pendingLPFee0, amount0);
        }
        if (amount1 > _feesOwed1[owner] || amount1 > _pendingLPFee1) {
            revert AuralisAccountingDeficit(token1, _pendingLPFee1, amount1);
        }

        unchecked {
            _feesOwed0[owner] -= amount0;
            _feesOwed1[owner] -= amount1;
            _pendingLPFee0 -= AuralisMath.toUint128(amount0);
            _pendingLPFee1 -= AuralisMath.toUint128(amount1);
        }
    }

    function _redemptionQuote(
        address owner,
        uint256 liquidity
    ) internal view returns (BurnQuote memory result) {
        (uint112 active0, uint112 active1) = activeReserves();
        (uint256 accrued0, uint256 accrued1) = accruedFees(owner);
        LiquiditySettlement.Context memory context = LiquiditySettlement.Context({
            liquidity: liquidity,
            totalSupply: totalSupply,
            ownerBalance: balanceOf[owner],
            grossReserve0: _reserve0,
            grossReserve1: _reserve1,
            activeReserve0: active0,
            activeReserve1: active1,
            accruedFee0: accrued0,
            accruedFee1: accrued1,
            feeBalances: _feeBalances()
        });
        LiquiditySettlement.Quote memory quote = LiquiditySettlement.quote(context);
        result = BurnQuote({
            amount0: quote.amount0,
            amount1: quote.amount1,
            principal0: quote.principal0,
            principal1: quote.principal1,
            realizedFee0: quote.realizedFee0,
            realizedFee1: quote.realizedFee1,
            closesPosition: quote.closesPosition
        });
    }

    function _pullExact(
        address token,
        address from,
        uint256 amount
    ) internal {
        uint256 balanceBefore = token.safeBalanceOf(address(this));
        token.safeTransferFrom(from, address(this), amount);
        uint256 balanceAfter = token.safeBalanceOf(address(this));
        uint256 received = balanceAfter >= balanceBefore ? balanceAfter - balanceBefore : 0;
        if (received != amount) revert AuralisUnsupportedToken(token, amount, received);
    }

    function _writeReserves(
        uint256 balance0,
        uint256 balance1,
        bool validateComposition
    ) internal {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) {
            revert AuralisInvalidConfiguration();
        }
        ReserveMath.FeeBalances memory fees = _feeBalances();
        (uint112 active0, uint112 active1) = ReserveMath.activeReserves(balance0, balance1, fees);
        if (validateComposition && totalSupply > AuralisConstants.MINIMUM_LIQUIDITY) {
            _checkComposition(active0, active1);
        }

        // Values are bounded explicitly above.
        // forge-lint: disable-next-line(unsafe-typecast)
        _reserve0 = uint112(balance0);
        // forge-lint: disable-next-line(unsafe-typecast)
        _reserve1 = uint112(balance1);
        _blockTimestampLast = uint32(block.timestamp);
        emit Sync(_reserve0, _reserve1);

        _updateOracle(active0, active1);
    }

    function _updateOracle(
        uint112 active0,
        uint112 active1
    ) internal {
        address configuredOracle = oracle;
        if (configuredOracle == address(0)) return;
        try IAuralisOracle(configuredOracle).update(active0, active1) { } catch { }
    }

    function _feeQuote(
        bool zeroForOne,
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal view returns (uint24 feePpm, uint24 protocolSharePpm) {
        address controller = IAuralisFactory(factory).feeController();
        if (controller == address(0)) return (DEFAULT_FEE_PPM, 0);
        return IAuralisFeeController(controller)
            .quoteFee(address(this), zeroForOne, amountIn, reserveIn, reserveOut);
    }

    function _feeBalances() internal view returns (ReserveMath.FeeBalances memory fees) {
        fees = ReserveMath.FeeBalances({
            lpFee0: _pendingLPFee0,
            lpFee1: _pendingLPFee1,
            protocolFee0: _protocolFee0,
            protocolFee1: _protocolFee1
        });
    }

    function _riskConfiguration() internal view returns (PoolRiskConfig memory configuration) {
        configuration = IAuralisImbalanceGuard(imbalanceGuard).riskConfig(address(this));
    }

    function _checkComposition(
        uint256 reserve0,
        uint256 reserve1
    ) internal view {
        IAuralisImbalanceGuard(imbalanceGuard)
            .checkVirtualReserves(address(this), reserve0, reserve1);
    }

    function _zeroForOne(
        address tokenIn
    ) internal view returns (bool zeroForOne) {
        if (tokenIn == token0) return true;
        if (tokenIn == token1) return false;
        revert AuralisInvalidToken(tokenIn);
    }

    function _requireOperational() internal view {
        if (paused) revert AuralisPoolPaused();
    }

    function _requireDeadline(
        uint256 deadline
    ) internal view {
        // Miner latitude is negligible relative to user-selected transaction deadlines.
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp > deadline) {
            revert AuralisDeadlineExpired(deadline, block.timestamp);
        }
    }

    function _transfer(
        address from,
        address to,
        uint256 value
    ) internal override {
        _accrueAccount(from);
        if (to != from) _accrueAccount(to);
        super._transfer(from, to, value);
    }

    function _mint(
        address to,
        uint256 value
    ) internal override {
        _accrueAccount(to);
        super._mint(to, value);
    }

    function _burn(
        address from,
        uint256 value
    ) internal override {
        _accrueAccount(from);
        super._burn(from, value);
    }
}
