// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { AuralisPool } from "../../src/core/AuralisPool.sol";
import { DynamicFeeController } from "../../src/fees/DynamicFeeController.sol";
import { IAuralisFactory } from "../../src/interfaces/IAuralisFactory.sol";
import { AuralisOracle } from "../../src/oracle/AuralisOracle.sol";
import { Ownable2Step } from "../../src/utils/Ownable2Step.sol";
import { PoolTestBase } from "../helpers/PoolTestBase.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

contract AuralisFactoryTest is PoolTestBase {
    function test_CreatedPoolIsCanonicalAndEnumerable() public view {
        assertEq(factory.getPool(address(token0), address(token1)), address(pool));
        assertEq(factory.getPool(address(token1), address(token0)), address(pool));
        assertEq(factory.allPoolsLength(), 1);
        assertEq(factory.allPools(0), address(pool));
        assertTrue(factory.isPool(address(pool)));
        assertEq(pool.factory(), address(factory));
        assertEq(pool.token0(), address(token0));
        assertEq(pool.token1(), address(token1));
    }

    function test_FactoryAttachesCompatibleOracle() public view {
        address oracle = factory.poolOracle(address(pool));

        assertTrue(oracle != address(0));
        assertEq(pool.oracle(), oracle);
        assertEq(AuralisOracle(oracle).pool(), address(pool));
        assertEq(AuralisOracle(oracle).minimumObservationInterval(), 60);
    }

    function test_PredictedAddressMatchesDeploymentForEitherTokenOrder() public {
        MockERC20 assetC = new MockERC20("Asset C", "C", 18);
        MockERC20 assetD = new MockERC20("Asset D", "D", 18);
        address forward = factory.predictPoolAddress(address(assetC), address(assetD));
        address reverse = factory.predictPoolAddress(address(assetD), address(assetC));

        address deployed = factory.createPool(address(assetD), address(assetC));

        assertEq(forward, reverse);
        assertEq(deployed, forward);
    }

    function test_OwnerCanUpdateSharedFeeConfiguration() public {
        DynamicFeeController replacement = new DynamicFeeController(address(this));
        address newRecipient = address(0x1234);

        factory.setFeeController(address(replacement));
        factory.setProtocolFeeRecipient(newRecipient);

        assertEq(factory.feeController(), address(replacement));
        assertEq(factory.protocolFeeRecipient(), newRecipient);
    }

    function test_GuardianCanPausePoolAndOwnerCanResumeIt() public {
        vm.prank(GUARDIAN);
        factory.setPoolPaused(address(pool), true);
        assertTrue(pool.paused());

        factory.setPoolPaused(address(pool), false);
        assertFalse(pool.paused());
    }

    function test_GuardianCanPausePoolCreation() public {
        vm.prank(GUARDIAN);
        factory.setCreationPaused(true);
        assertTrue(factory.creationPaused());

        factory.setCreationPaused(false);
        assertFalse(factory.creationPaused());
    }

    function test_UpdatedObservationIntervalAppliesToNewPools() public {
        factory.setOracleObservationInterval(5 minutes);
        MockERC20 assetC = new MockERC20("Asset C", "C", 18);
        MockERC20 assetD = new MockERC20("Asset D", "D", 18);

        address newPool = factory.createPool(address(assetC), address(assetD));
        AuralisOracle oracle = AuralisOracle(factory.poolOracle(newPool));

        assertEq(oracle.minimumObservationInterval(), 5 minutes);
    }

    function test_OwnerCanReplacePoolOracle() public {
        AuralisOracle replacement = new AuralisOracle(address(pool), 30);

        factory.setPoolOracle(address(pool), address(replacement));

        assertEq(factory.poolOracle(address(pool)), address(replacement));
        assertEq(pool.oracle(), address(replacement));
    }

    function test_RevertWhenCreatingDuplicatePairInReverseOrder() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAuralisFactory.PoolAlreadyExists.selector, address(token0), address(token1)
            )
        );
        factory.createPool(address(token1), address(token0));
    }

    function test_RevertWhenCreatingPoolWithIdenticalTokens() public {
        vm.expectRevert(IAuralisFactory.IdenticalTokens.selector);
        factory.createPool(address(token0), address(token0));
    }

    function test_RevertWhenCreatingPoolWithZeroAddress() public {
        vm.expectRevert(IAuralisFactory.ZeroAddress.selector);
        factory.createPool(address(0), address(token0));
    }

    function test_RevertWhenCreatingPoolWithNonContractAsset() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAuralisFactory.InvalidContract.selector, address(0x1234))
        );
        factory.createPool(address(token0), address(0x1234));
    }

    function test_RevertWhenCreationIsPaused() public {
        factory.setCreationPaused(true);
        MockERC20 assetC = new MockERC20("Asset C", "C", 18);
        MockERC20 assetD = new MockERC20("Asset D", "D", 18);

        vm.expectRevert(IAuralisFactory.PoolCreationPaused.selector);
        factory.createPool(address(assetC), address(assetD));
    }

    function test_RevertWhenGuardianAttemptsToUnpause() public {
        factory.setCreationPaused(true);

        vm.prank(GUARDIAN);
        vm.expectRevert(IAuralisFactory.GuardianCannotUnpause.selector);
        factory.setCreationPaused(false);
    }

    function test_RevertWhenNonOwnerUpdatesFeeController() public {
        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(Ownable2Step.Unauthorized.selector, BOB));
        factory.setFeeController(address(0));
    }

    function test_RevertWhenFeeControllerHasNoCode() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAuralisFactory.InvalidContract.selector, address(0x1234))
        );
        factory.setFeeController(address(0x1234));
    }

    function test_RevertWhenProtocolRecipientIsZero() public {
        vm.expectRevert(IAuralisFactory.ZeroAddress.selector);
        factory.setProtocolFeeRecipient(address(0));
    }

    function test_RevertWhenPausingUnknownPool() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAuralisFactory.UnknownPool.selector, address(0x1234))
        );
        factory.setPoolPaused(address(0x1234), true);
    }

    function test_RevertWhenOracleDoesNotReferencePool() public {
        AuralisPool otherPool = AuralisPool(
            payable(factory.createPool(
                    address(new MockERC20("Asset C", "C", 18)),
                    address(new MockERC20("Asset D", "D", 18))
                ))
        );
        AuralisOracle wrongOracle = new AuralisOracle(address(otherPool), 30);

        vm.expectRevert();
        factory.setPoolOracle(address(pool), address(wrongOracle));
    }
}
