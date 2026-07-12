// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IAuralisFactory } from "../src/interfaces/IAuralisFactory.sol";
import { IAuralisPool } from "../src/interfaces/IAuralisPool.sol";

interface VmSeedPool {
    function addr(
        uint256 privateKey
    ) external returns (address keyAddr);

    function envAddress(
        string calldata name
    ) external returns (address value);

    function envUint(
        string calldata name
    ) external returns (uint256 value);

    function envOr(
        string calldata name,
        address defaultValue
    ) external returns (address value);

    function envOr(
        string calldata name,
        uint256 defaultValue
    ) external returns (uint256 value);

    function startBroadcast(
        uint256 privateKey
    ) external;

    function stopBroadcast() external;
}

interface FeeConfigurator {
    function owner() external view returns (address);

    function configurePool(
        address pool,
        address oracle,
        uint128 anchorReserve0,
        uint128 anchorReserve1,
        uint32 volatilityWindow,
        bool oracleEnabled
    ) external;
}

/// @notice Creates a canonical pool when needed and supplies its opening liquidity.
contract SeedPool {
    error InvalidSeedConfiguration();
    error ApprovalFailed(address token);

    event PoolSeeded(
        address indexed pool,
        address indexed provider,
        address indexed recipient,
        uint256 amount0,
        uint256 amount1,
        uint256 liquidity,
        bool feeControllerConfigured
    );

    VmSeedPool private constant VM =
        VmSeedPool(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes4 private constant APPROVE_SELECTOR = 0x095ea7b3;

    struct SeedConfiguration {
        IAuralisFactory factory;
        address provider;
        address recipient;
        address tokenA;
        address tokenB;
        uint256 amountA;
        uint256 amountB;
        uint256 deadlineWindow;
        uint32 volatilityWindow;
    }

    function run()
        external
        returns (address pool, uint256 amount0, uint256 amount1, uint256 liquidity)
    {
        uint256 privateKey = VM.envUint("PRIVATE_KEY");
        SeedConfiguration memory configuration = _readConfiguration(privateKey);
        uint256 desired0 = configuration.tokenA < configuration.tokenB
            ? configuration.amountA
            : configuration.amountB;
        uint256 desired1 = configuration.tokenA < configuration.tokenB
            ? configuration.amountB
            : configuration.amountA;

        VM.startBroadcast(privateKey);
        pool = configuration.factory.getPool(configuration.tokenA, configuration.tokenB);
        if (pool == address(0)) {
            pool = configuration.factory.createPool(configuration.tokenA, configuration.tokenB);
        }
        _approve(configuration.tokenA, pool, configuration.amountA);
        _approve(configuration.tokenB, pool, configuration.amountB);
        (amount0, amount1, liquidity) = IAuralisPool(pool)
            .mint(
                configuration.recipient,
                desired0,
                desired1,
                0,
                0,
                block.timestamp + configuration.deadlineWindow
            );
        bool configured = _configureFees(
            configuration.factory, pool, configuration.provider, configuration.volatilityWindow
        );
        VM.stopBroadcast();

        emit PoolSeeded(
            pool,
            configuration.provider,
            configuration.recipient,
            amount0,
            amount1,
            liquidity,
            configured
        );
    }

    function _readConfiguration(
        uint256 privateKey
    ) internal returns (SeedConfiguration memory configuration) {
        configuration.provider = VM.addr(privateKey);
        configuration.factory = IAuralisFactory(VM.envAddress("AURALIS_FACTORY"));
        configuration.tokenA = VM.envAddress("TOKEN_A");
        configuration.tokenB = VM.envAddress("TOKEN_B");
        configuration.amountA = VM.envUint("AMOUNT_A");
        configuration.amountB = VM.envUint("AMOUNT_B");
        configuration.recipient = VM.envOr("LP_RECIPIENT", configuration.provider);
        configuration.deadlineWindow = VM.envOr("DEADLINE_WINDOW", uint256(3600));
        uint256 volatilityWindow = VM.envOr("VOLATILITY_WINDOW", uint256(1800));
        if (
            configuration.tokenA == address(0) || configuration.tokenB == address(0)
                || configuration.tokenA == configuration.tokenB || configuration.amountA == 0
                || configuration.amountB == 0 || configuration.recipient == address(0)
                || configuration.deadlineWindow == 0 || volatilityWindow == 0
                || volatilityWindow > type(uint32).max
        ) revert InvalidSeedConfiguration();
        // The volatility window was bounded to uint32 above.
        // forge-lint: disable-next-line(unsafe-typecast)
        configuration.volatilityWindow = uint32(volatilityWindow);
    }

    function _configureFees(
        IAuralisFactory factory,
        address pool,
        address provider,
        uint32 volatilityWindow
    ) internal returns (bool configured) {
        address controller = factory.feeController();
        if (controller == address(0)) return false;
        try FeeConfigurator(controller).owner() returns (address controllerOwner) {
            if (controllerOwner != provider) return false;
        } catch {
            return false;
        }

        (uint112 reserve0, uint112 reserve1) = IAuralisPool(pool).activeReserves();
        address oracle = factory.poolOracle(pool);
        FeeConfigurator(controller)
            .configurePool(pool, oracle, reserve0, reserve1, volatilityWindow, oracle != address(0));
        configured = true;
    }

    function _approve(
        address token,
        address spender,
        uint256 amount
    ) internal {
        (bool success, bytes memory returnData) =
            token.call(abi.encodeWithSelector(APPROVE_SELECTOR, spender, amount));
        if (!success || (returnData.length != 0 && !abi.decode(returnData, (bool)))) {
            revert ApprovalFailed(token);
        }
    }
}
