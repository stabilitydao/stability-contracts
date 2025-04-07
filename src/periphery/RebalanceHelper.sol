// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IALM} from "../interfaces/IALM.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {ILPStrategy} from "../interfaces/ILPStrategy.sol";
import {ICAmmAdapter} from "../interfaces/ICAmmAdapter.sol";
import {ALMLib} from "../strategies/libs/ALMLib.sol";

/// @title ALM re-balancing helper that calculate args for rebalance() call
/// Changelog:
///   1.0.2: calcRebalanceArgs bugfix
///   1.0.1: calcRebalanceArgs bugfix
/// @author Alien Deployer (https://github.com/a17)
contract RebalanceHelper {
    string public constant VERSION = "1.0.2";
    uint internal constant SLIPPAGE_PRECISION = 100_000;

    struct CalcRebalanceVars {
        uint algoId;
        int24[] params;
        address pool;
        bool baseRebalanceNeeded;
        bool limitRebalanceNeeded;
        int24 currentTick;
        int24 tickSpacing;
        uint[] amounts;
    }

    /// @notice Calculate new position arguments for ALM re-balancing
    /// @param strategy Address of ALM strategy
    /// @param slippage Slippage check. 50_000 - 50%, 1_000 - 1%, 100 - 0.1%, 1 - 0.001%
    /// @return burnOldPositions Burn old positions or not.
    /// @return mintNewPositions New positions data
    function calcRebalanceArgs(
        address strategy,
        uint slippage
    ) external view returns (IALM.RebalanceAction[] memory burnOldPositions, IALM.NewPosition[] memory mintNewPositions) {
        if (!IERC165(strategy).supportsInterface(type(IALM).interfaceId)) {
            revert IALM.NotALM();
        }

        ILPStrategy lpStrategy = ILPStrategy(strategy);
        IALM almStrategy = IALM(strategy);

        CalcRebalanceVars memory v;
        (v.algoId,,, v.params) = almStrategy.preset();

        if (v.algoId != ALMLib.ALGO_FILL_UP)
            return (new IALM.RebalanceAction[](0), new IALM.NewPosition[](0));

        v.pool = lpStrategy.pool();
        ICAmmAdapter adapter = ICAmmAdapter(address(lpStrategy.ammAdapter()));
        v.currentTick = ALMLib.getUniswapV3CurrentTick(v.pool);
        v.tickSpacing = ALMLib.getUniswapV3TickSpacing(v.pool);
        (, v.amounts) = IStrategy(strategy).assetsAmounts();

        (v.baseRebalanceNeeded, v.limitRebalanceNeeded) = almStrategy.needRebalance();

        mintNewPositions = new IALM.NewPosition[](3);
        uint newPositionIndex = 0;
        bool isAssetsRemained = false;
        IALM.NewPosition memory remainedPosition;

        if (v.baseRebalanceNeeded) {
            (mintNewPositions[newPositionIndex], isAssetsRemained, remainedPosition) = _calculateBasePosition(
                strategy,
                adapter,
                v.pool,
                v.amounts,
                v.currentTick,
                v.tickSpacing,
                v.params,
                slippage
            );
            newPositionIndex++;
        }

        if (v.limitRebalanceNeeded) {
            mintNewPositions[newPositionIndex] = _calculateLimitPosition(
                strategy,
                adapter,
                v.pool,
                v.amounts,
                v.currentTick,
                v.params,
                slippage
            );
            newPositionIndex++;
        }

        if (isAssetsRemained) {
            mintNewPositions[newPositionIndex] = remainedPosition;
        }

        // Handle burnOldPositions
        IALM.Position[] memory existingPositions = almStrategy.positions();
        uint numExistingPositions = existingPositions.length;
        burnOldPositions = new IALM.RebalanceAction[](numExistingPositions);

        // Mark old positions for burning based on rebalance needs
        for (uint i = 0; i < numExistingPositions; i++) {
            if ((i == 0 && v.baseRebalanceNeeded) || (i == 1 && v.limitRebalanceNeeded) || (i == 2 && isAssetsRemained)) {
                burnOldPositions[i] = IALM.RebalanceAction.BURN; // Burn if rebalancing
            } else if (i == 2 && !isAssetsRemained) {
                burnOldPositions[i] = IALM.RebalanceAction.REMOVE; // Keep if not rebalancing
            } else {
                burnOldPositions[i] = IALM.RebalanceAction.KEEP; // Keep if not rebalancing
            }
        }
    }

    function _calculateBasePosition(
        address strategy,
        ICAmmAdapter adapter,
        address pool,
        uint[] memory amounts,
        int24 currentTick,
        int24 tickSpacing,
        int24[] memory params,
        uint slippage
    ) private view returns (IALM.NewPosition memory newPosition, bool isAssetsRemained, IALM.NewPosition memory remainedPosition) {
        IALM.Position memory oldBasePosition = IALM(strategy).positions()[0];
        int24 tickLower;
        int24 tickUpper;

        isAssetsRemained = false;

        if (currentTick > oldBasePosition.tickUpper || currentTick < oldBasePosition.tickLower) {
            (tickLower, tickUpper) = _calculateOutOfRangeTicks(currentTick, oldBasePosition, tickSpacing);
        } else {
            (tickLower, tickUpper) = ALMLib.calcFillUpBaseTicks(currentTick, params[0], tickSpacing);
            isAssetsRemained = true;
        }

        int24[] memory ticks = new int24[](2);
        ticks[0] = tickLower;
        ticks[1] = tickUpper;

        (uint addedLiquidity, uint[] memory amountsConsumed) = adapter.getLiquidityForAmounts(pool, amounts, ticks);

        newPosition.tickLower = tickLower;
        newPosition.tickUpper = tickUpper;
        newPosition.liquidity = uint128(addedLiquidity);
        newPosition.minAmount0 = amountsConsumed[0] - (amountsConsumed[0] * slippage / SLIPPAGE_PRECISION);
        newPosition.minAmount1 = amountsConsumed[1] - (amountsConsumed[1] * slippage / SLIPPAGE_PRECISION);

        if (isAssetsRemained) {
            // calc fill-up
            uint[] memory amountsRemaining = new uint[](2);
            amountsRemaining[0] = amounts[0] - amountsConsumed[0];
            amountsRemaining[1] = amounts[1] - amountsConsumed[1];
            //bool intDiv = currentTick / tickSpacing * tickSpacing == currentTick;
            int24[] memory fillUpTicksLowerSide = new int24[](2);
            fillUpTicksLowerSide[0] = tickLower;
            //slither-disable-next-line divide-before-multiply
            fillUpTicksLowerSide[1] =
                currentTick > 0 ? (currentTick / tickSpacing * tickSpacing) : (currentTick / tickSpacing * tickSpacing - tickSpacing);
            int24[] memory fillUpTicksUpperSide = new int24[](2);
            //slither-disable-next-line divide-before-multiply
            fillUpTicksUpperSide[0] =
                currentTick > 0 ? (currentTick / tickSpacing * tickSpacing + tickSpacing) : (currentTick / tickSpacing * tickSpacing);
            fillUpTicksUpperSide[1] = tickUpper;
            (uint fillUpLiquidityLowerSide, uint[] memory fillUpAmountsConsumedLowerSide) =
                adapter.getLiquidityForAmounts(pool, amountsRemaining, fillUpTicksLowerSide);
            (uint fillUpLiquidityUpperSide, uint[] memory fillUpAmountsConsumedUpperSide) =
                adapter.getLiquidityForAmounts(pool, amountsRemaining, fillUpTicksUpperSide);
            if (fillUpLiquidityLowerSide > fillUpLiquidityUpperSide) {
                remainedPosition.tickLower = fillUpTicksLowerSide[0];
                remainedPosition.tickUpper = fillUpTicksLowerSide[1];
                remainedPosition.liquidity = uint128(fillUpLiquidityLowerSide);
                remainedPosition.minAmount0 = fillUpAmountsConsumedLowerSide[0]
                    - fillUpAmountsConsumedLowerSide[0] * slippage / SLIPPAGE_PRECISION;
                remainedPosition.minAmount1 = fillUpAmountsConsumedLowerSide[1]
                    - fillUpAmountsConsumedLowerSide[1] * slippage / SLIPPAGE_PRECISION;
            } else {
                remainedPosition.tickLower = fillUpTicksUpperSide[0];
                remainedPosition.tickUpper = fillUpTicksUpperSide[1];
                remainedPosition.liquidity = uint128(fillUpLiquidityUpperSide);
                remainedPosition.minAmount0 = fillUpAmountsConsumedUpperSide[0]
                    - fillUpAmountsConsumedUpperSide[0] * slippage / SLIPPAGE_PRECISION;
                remainedPosition.minAmount1 = fillUpAmountsConsumedUpperSide[1]
                    - fillUpAmountsConsumedUpperSide[1] * slippage / SLIPPAGE_PRECISION;
            }
        }
    }

    function _calculateLimitPosition(
        address strategy,
        ICAmmAdapter adapter,
        address pool,
        uint[] memory amounts,
        int24 currentTick,
        int24[] memory params,
        uint slippage
    ) private view returns (IALM.NewPosition memory newPosition) {
        // In ALMStrategy initialization:
        // int24[] memory params = new int24[](3);
        // params[0] = 600;  // Base range size (ticks)
        // params[1] = 300;  // Base trigger threshold (ticks)
        // params[2] = 900;  // Limit range size (ticks)

        IALM.Position memory oldBasePosition = IALM(strategy).positions()[0];
        int24 tickLower;
        int24 tickUpper;

        if (currentTick > oldBasePosition.tickUpper) {
            tickLower = oldBasePosition.tickUpper;
            tickUpper = oldBasePosition.tickUpper + params[2];
        } else {
            tickLower = oldBasePosition.tickLower - params[2];
            tickUpper = oldBasePosition.tickLower;
        }

        int24[] memory ticks = new int24[](2);
        ticks[0] = tickLower;
        ticks[1] = tickUpper;

        (uint addedLiquidity, uint[] memory amountsConsumed) = adapter.getLiquidityForAmounts(pool, amounts, ticks);

        newPosition.tickLower = tickLower;
        newPosition.tickUpper = tickUpper;
        newPosition.liquidity = uint128(addedLiquidity);
        newPosition.minAmount0 = amountsConsumed[0] - (amountsConsumed[0] * slippage / SLIPPAGE_PRECISION);
        newPosition.minAmount1 = amountsConsumed[1] - (amountsConsumed[1] * slippage / SLIPPAGE_PRECISION);
    }

    function _calculateOutOfRangeTicks(
        int24 currentTick,
        IALM.Position memory oldBasePosition,
        int24 tickSpacing
    ) private pure returns (int24 tickLower, int24 tickUpper) {
        if (currentTick > oldBasePosition.tickUpper) {
            int24 tickDistance = currentTick - oldBasePosition.tickUpper;
            tickDistance = tickDistance / tickSpacing * tickSpacing;
            if (tickDistance == 0) {
                revert IALM.CantDoRebalance();
            }
            tickLower = oldBasePosition.tickLower + tickDistance;
            tickUpper = oldBasePosition.tickUpper + tickDistance;
        } else {
            int24 tickDistance = oldBasePosition.tickLower - currentTick;
            tickDistance = tickDistance / tickSpacing * tickSpacing;
            if (tickDistance == 0) {
                revert IALM.CantDoRebalance();
            }
            tickLower = oldBasePosition.tickLower - tickDistance;
            tickUpper = oldBasePosition.tickUpper - tickDistance;
        }
    }
}
