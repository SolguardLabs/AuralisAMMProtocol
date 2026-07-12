// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { AuralisFactory } from "../../src/core/AuralisFactory.sol";
import { AuralisPool } from "../../src/core/AuralisPool.sol";
import { DynamicFeeController } from "../../src/fees/DynamicFeeController.sol";
import { ImbalanceGuard } from "../../src/risk/ImbalanceGuard.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { TestBase } from "./TestBase.sol";

abstract contract PoolTestBase is TestBase {
    uint256 internal constant INITIAL_LIQUIDITY = 1_000_000 ether;
    uint256 internal constant DEFAULT_SWAP_INPUT = 10_000 ether;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant TRADER = address(0x7A6E);
    address internal constant GUARDIAN = address(0x600D);
    address internal constant PROTOCOL_RECIPIENT = address(0xFEE);

    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    MockERC20 internal token0;
    MockERC20 internal token1;

    ImbalanceGuard internal guard;
    DynamicFeeController internal feeController;
    AuralisFactory internal factory;
    AuralisPool internal pool;

    function setUp() public virtual {
        vm.warp(10 days);
        tokenA = new MockERC20("Auralis Asset A", "AURA-A", 18);
        tokenB = new MockERC20("Auralis Asset B", "AURA-B", 18);
        (token0, token1) = address(tokenA) < address(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);

        guard = new ImbalanceGuard(address(this));
        feeController = new DynamicFeeController(address(this));
        feeController.setFeeParameters(10_000, 10_000, 10_000, 0, 0, 0);
        feeController.setProtocolFeeShare(200_000);

        factory = new AuralisFactory(
            address(this), address(guard), address(feeController), PROTOCOL_RECIPIENT, GUARDIAN, 60
        );
        pool = AuralisPool(payable(factory.createPool(address(tokenA), address(tokenB))));

        _fundAndApprove(ALICE, 5_000_000 ether);
        _fundAndApprove(BOB, 5_000_000 ether);
        _fundAndApprove(TRADER, 5_000_000 ether);

        vm.label(address(pool), "Auralis pool");
        vm.label(ALICE, "Alice LP");
        vm.label(BOB, "Bob LP");
        vm.label(TRADER, "Trader");
    }

    function _fundAndApprove(
        address account,
        uint256 amount
    ) internal {
        token0.mint(account, amount);
        token1.mint(account, amount);
        vm.startPrank(account);
        token0.approve(address(pool), type(uint256).max);
        token1.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    function _initializePool() internal returns (uint256 liquidity) {
        vm.prank(ALICE);
        (,, liquidity) = pool.mint(
            ALICE,
            INITIAL_LIQUIDITY,
            INITIAL_LIQUIDITY,
            INITIAL_LIQUIDITY,
            INITIAL_LIQUIDITY,
            block.timestamp
        );
    }

    function _swap(
        address account,
        MockERC20 tokenIn,
        uint256 amountIn
    ) internal returns (uint256 amountOut) {
        vm.prank(account);
        amountOut = pool.swapExactInput(address(tokenIn), amountIn, 0, account, block.timestamp);
    }

    function _grossReserves() internal view returns (uint256 reserve0, uint256 reserve1) {
        (uint112 stored0, uint112 stored1,) = pool.getReserves();
        reserve0 = stored0;
        reserve1 = stored1;
    }

    function _assertAccountingReconciles() internal view {
        (uint256 gross0, uint256 gross1) = _grossReserves();
        (uint112 active0, uint112 active1) = pool.activeReserves();
        (uint128 pending0, uint128 pending1) = pool.pendingLPFees();
        (uint128 protocol0, uint128 protocol1) = pool.protocolFees();

        assertEq(gross0, uint256(active0) + pending0 + protocol0);
        assertEq(gross1, uint256(active1) + pending1 + protocol1);
        assertEq(gross0, token0.balanceOf(address(pool)));
        assertEq(gross1, token1.balanceOf(address(pool)));
    }
}
