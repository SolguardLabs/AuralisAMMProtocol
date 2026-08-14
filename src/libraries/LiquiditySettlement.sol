// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { AuralisMath } from "./AuralisMath.sol";
import { ReserveMath } from "./ReserveMath.sol";

/// @title Liquidity settlement arithmetic
/// @notice Builds deterministic redemption quotes from pool accounting state.
library LiquiditySettlement {
    /// @notice State required to price one LP redemption.
    struct Context {
        uint256 liquidity;
        uint256 totalSupply;
        uint256 ownerBalance;
        uint256 grossReserve0;
        uint256 grossReserve1;
        uint256 activeReserve0;
        uint256 activeReserve1;
        uint256 accruedFee0;
        uint256 accruedFee1;
        ReserveMath.FeeBalances feeBalances;
    }

    /// @notice Decomposed redemption result consumed by pools and view contracts.
    struct Quote {
        uint256 amount0;
        uint256 amount1;
        uint256 principal0;
        uint256 principal1;
        uint256 realizedFee0;
        uint256 realizedFee1;
        bool closesPosition;
    }

    /// @notice Prices a redemption and separates principal from realized fee entitlement.
    function quote(
        Context memory context
    ) internal pure returns (Quote memory result) {
        result.closesPosition = context.liquidity == context.ownerBalance;

        if (result.closesPosition) {
            (result.principal0, result.principal1) = ReserveMath.withdrawalAmounts(
                context.liquidity,
                context.totalSupply,
                context.activeReserve0,
                context.activeReserve1
            );
            result.realizedFee0 = AuralisMath.min(context.accruedFee0, context.feeBalances.lpFee0);
            result.realizedFee1 = AuralisMath.min(context.accruedFee1, context.feeBalances.lpFee1);
            result.amount0 = result.principal0 + result.realizedFee0;
            result.amount1 = result.principal1 + result.realizedFee1;
            return result;
        }

        (uint256 owned0, uint256 owned1) = ReserveMath.lpOwnedBalances(
            context.grossReserve0, context.grossReserve1, context.feeBalances
        );
        (result.principal0, result.principal1) =
            ReserveMath.withdrawalAmounts(context.liquidity, context.totalSupply, owned0, owned1);
        result.amount0 = result.principal0;
        result.amount1 = result.principal1;
    }
}
