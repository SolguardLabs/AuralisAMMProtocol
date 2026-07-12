// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { AuralisPool } from "../../src/core/AuralisPool.sol";
import { InvariantBase } from "../helpers/InvariantBase.sol";
import { PoolTestBase } from "../helpers/PoolTestBase.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

contract PoolActionHandler {
    error TokenTransferFailed();

    AuralisPool public immutable pool;
    MockERC20 public immutable token0;
    MockERC20 public immutable token1;

    constructor(
        AuralisPool pool_,
        MockERC20 token0_,
        MockERC20 token1_
    ) {
        pool = pool_;
        token0 = token0_;
        token1 = token1_;
        token0_.approve(address(pool_), type(uint256).max);
        token1_.approve(address(pool_), type(uint256).max);
    }

    function swapToken0(
        uint96 rawAmount
    ) external {
        uint256 available = token0.balanceOf(address(this));
        if (available == 0) return;
        uint256 maximum = available < 1000 ether ? available : 1000 ether;
        uint256 amount = 1 + (uint256(rawAmount) % maximum);
        pool.swapExactInput(address(token0), amount, 0, address(this), block.timestamp);
    }

    function swapToken1(
        uint96 rawAmount
    ) external {
        uint256 available = token1.balanceOf(address(this));
        if (available == 0) return;
        uint256 maximum = available < 1000 ether ? available : 1000 ether;
        uint256 amount = 1 + (uint256(rawAmount) % maximum);
        pool.swapExactInput(address(token1), amount, 0, address(this), block.timestamp);
    }

    function claimFees() external {
        pool.claimFees(address(this));
    }

    function collectProtocolFees() external {
        pool.collectProtocolFees();
    }

    function donateAndSkim(
        uint96 rawAmount0,
        uint96 rawAmount1
    ) external {
        uint256 amount0 = uint256(rawAmount0) % (100 ether);
        uint256 amount1 = uint256(rawAmount1) % (100 ether);
        if (amount0 <= token0.balanceOf(address(this))) {
            if (!token0.transfer(address(pool), amount0)) revert TokenTransferFailed();
        }
        if (amount1 <= token1.balanceOf(address(this))) {
            if (!token1.transfer(address(pool), amount1)) revert TokenTransferFailed();
        }
        pool.skim(address(this));
    }
}

contract AuralisPoolInvariantTest is PoolTestBase, InvariantBase {
    address internal constant MINIMUM_LIQUIDITY_HOLDER = address(0xdead);

    PoolActionHandler internal handler;
    uint256 internal initialInvariant;
    uint256 internal initialSupply;

    function setUp() public override {
        super.setUp();
        uint256 minted = _initializePool();
        handler = new PoolActionHandler(pool, token0, token1);
        token0.mint(address(handler), 5_000_000 ether);
        token1.mint(address(handler), 5_000_000 ether);

        vm.prank(ALICE);
        assertTrue(pool.transfer(address(handler), minted / 4));

        (uint112 reserve0, uint112 reserve1) = pool.activeReserves();
        initialInvariant = uint256(reserve0) * uint256(reserve1);
        initialSupply = pool.totalSupply();
        targetContract(address(handler));
    }

    function invariant_GrossBalancesReconcileWithActiveReservesAndFees() public view {
        _assertAccountingReconciles();

        (uint128 pending0, uint128 pending1) = pool.pendingLPFees();
        (uint128 protocol0, uint128 protocol1) = pool.protocolFees();
        (uint256 obligation0, uint256 obligation1) = pool.accountedObligations();
        assertEq(obligation0, uint256(pending0) + protocol0);
        assertEq(obligation1, uint256(pending1) + protocol1);
    }

    function invariant_ConstantProductDoesNotDecrease() public view {
        (uint112 reserve0, uint112 reserve1) = pool.activeReserves();
        assertGe(uint256(reserve0) * uint256(reserve1), initialInvariant);
        assertGe(reserve0, pool.minimumReserve());
        assertGe(reserve1, pool.minimumReserve());
    }

    function invariant_ShareSupplyRemainsFullyAllocated() public view {
        assertEq(pool.totalSupply(), initialSupply);
        uint256 allocated = pool.balanceOf(ALICE) + pool.balanceOf(address(handler))
            + pool.balanceOf(MINIMUM_LIQUIDITY_HOLDER);
        assertEq(allocated, initialSupply);
    }
}
