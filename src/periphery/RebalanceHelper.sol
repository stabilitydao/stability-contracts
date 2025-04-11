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
        uint addedLiquidity;
        uint[] amountsConsumed;
        int24 lowerTickLower;
        int24 lowerTickUpper;
        int24 upperTickLower;
        int24 upperTickUpper;
        int24[] fillUpTicksLowerSide;
        int24[] fillUpTicksUpperSide;
        uint fillUpLiquidityLowerSide;
        uint fillUpLiquidityUpperSide;
        uint[] fillUpAmountsConsumedLowerSide;
        uint[] fillUpAmountsConsumedUpperSide;
    }

    /// @notice Calculate new position arguments for ALM re-balancing
    /// @param strategy Address of ALM strategy
    /// @param slippage Slippage check. 50_000 - 50%, 1_000 - 1%, 100 - 0.1%, 1 - 0.001%
    /// @return burnOldPositions Burn old positions or not.
    /// @return mintNewPositions New positions data
    function calcRebalanceArgs(
        address strategy,
        uint slippage
    ) external view returns (bool[] memory burnOldPositions, IALM.NewPosition[] memory mintNewPositions) {
        // Validate strategy interface
        if (!IERC165(strategy).supportsInterface(type(IALM).interfaceId)) {
            revert IALM.NotALM();
        }

        if (!IALM(strategy).needRebalance()) {
            revert IALM.NotNeedRebalance();
        }

        // Initialize variables using CalcRebalanceVars struct
        CalcRebalanceVars memory v;

        // Retrieve strategy preset and positions
        (v.algoId,,, v.params) = IALM(strategy).preset();

        v.pool = ILPStrategy(strategy).pool();
        v.tickSpacing = ALMLib.getUniswapV3TickSpacing(v.pool);
        v.currentTick = ALMLib.getUniswapV3CurrentTick(v.pool);
        ICAmmAdapter adapter = ICAmmAdapter(address(ILPStrategy(strategy).ammAdapter()));
        // slither-disable-next-line unused-return
        (, v.amounts) = IStrategy(strategy).assetsAmounts();
        IALM.Position[] memory positions = IALM(strategy).positions();
        uint positionsLength = positions.length;

        burnOldPositions = new bool[](positionsLength); // Initialize burnOldPositions array

        // Handle ALGO_FILL_UP logic
        if (v.algoId == ALMLib.ALGO_FILL_UP && positionsLength > 0) {
            IALM.Position memory oldBasePosition = positions[0];

            // Determine if base position needs rebalancing
            v.baseRebalanceNeeded =
                (v.currentTick < oldBasePosition.tickLower || v.currentTick > oldBasePosition.tickUpper);

            if (v.baseRebalanceNeeded) {
                // Mark all positions for burning if base position is out of range
                for (uint i = 0; i < positionsLength; i++) {
                    burnOldPositions[i] = true;
                }

                mintNewPositions = new IALM.NewPosition[](1);

                int24 tickDistance;

                if (v.currentTick > oldBasePosition.tickUpper) {
                    tickDistance = (v.currentTick - oldBasePosition.tickUpper) / v.tickSpacing * v.tickSpacing;
                    mintNewPositions[0].tickLower = oldBasePosition.tickLower + tickDistance;
                    mintNewPositions[0].tickUpper = oldBasePosition.tickUpper + tickDistance;
                } else {
                    tickDistance = (oldBasePosition.tickLower - v.currentTick) / v.tickSpacing * v.tickSpacing;
                    mintNewPositions[0].tickLower = oldBasePosition.tickLower - tickDistance;
                    mintNewPositions[0].tickUpper = oldBasePosition.tickUpper - tickDistance;
                }

                if (tickDistance == 0) {
                    revert IALM.CantDoRebalance();
                }

                int24[] memory ticks = new int24[](2);
                ticks[0] = mintNewPositions[0].tickLower;
                ticks[1] = mintNewPositions[0].tickUpper;

                (v.addedLiquidity, v.amountsConsumed) = adapter.getLiquidityForAmounts(v.pool, v.amounts, ticks);

                mintNewPositions[0].liquidity = uint128(v.addedLiquidity);
                mintNewPositions[0].minAmount0 =
                    v.amountsConsumed[0] - (v.amountsConsumed[0] * slippage) / SLIPPAGE_PRECISION;
                mintNewPositions[0].minAmount1 =
                    v.amountsConsumed[1] - (v.amountsConsumed[1] * slippage) / SLIPPAGE_PRECISION;
            } else {
                // Mark only non-base positions for burning
                for (uint i = 0; i < positionsLength; i++) {
                    burnOldPositions[i] = true;
                }

                mintNewPositions = new IALM.NewPosition[](2);

                // Calculate base position ticks
                (mintNewPositions[0].tickLower, mintNewPositions[0].tickUpper) =
                    ALMLib.calcFillUpBaseTicks(v.currentTick, v.params[0], v.tickSpacing);

                int24[] memory baseTicks = new int24[](2);
                baseTicks[0] = mintNewPositions[0].tickLower;
                baseTicks[1] = mintNewPositions[0].tickUpper;

                // Calculate liquidity and consumed amounts for base position
                (v.addedLiquidity, v.amountsConsumed) = adapter.getLiquidityForAmounts(v.pool, v.amounts, baseTicks);

                mintNewPositions[0].liquidity = uint128(v.addedLiquidity);
                mintNewPositions[0].minAmount0 =
                    v.amountsConsumed[0] - (v.amountsConsumed[0] * slippage) / SLIPPAGE_PRECISION;
                mintNewPositions[0].minAmount1 =
                    v.amountsConsumed[1] - (v.amountsConsumed[1] * slippage) / SLIPPAGE_PRECISION;

                // Calculate remaining asset amounts for fill-up position
                uint[] memory amountsRemaining = new uint[](2);
                amountsRemaining[0] = v.amounts[0] - v.amountsConsumed[0];
                amountsRemaining[1] = v.amounts[1] - v.amountsConsumed[1];

                // Calculate fill-up ticks on both sides of the current price
                v.lowerTickLower = v.currentTick > 0
                    ? (v.currentTick / v.tickSpacing * v.tickSpacing)
                    : ((v.currentTick / v.tickSpacing * v.tickSpacing) - v.tickSpacing);
                v.lowerTickUpper = v.lowerTickLower + v.tickSpacing;
                v.upperTickLower = v.lowerTickUpper;
                v.upperTickUpper = v.upperTickLower + v.tickSpacing;

                // Prepare tick arrays for liquidity comparison
                v.fillUpTicksLowerSide = new int24[](2);
                v.fillUpTicksLowerSide[0] = v.lowerTickLower;
                v.fillUpTicksLowerSide[1] = v.lowerTickUpper;

                v.fillUpTicksUpperSide = new int24[](2);
                v.fillUpTicksUpperSide[0] = v.upperTickLower;
                v.fillUpTicksUpperSide[1] = v.upperTickUpper;

                // Compare liquidity for both sides
                (v.fillUpLiquidityLowerSide, v.fillUpAmountsConsumedLowerSide) =
                    adapter.getLiquidityForAmounts(v.pool, amountsRemaining, v.fillUpTicksLowerSide);

                (v.fillUpLiquidityUpperSide, v.fillUpAmountsConsumedUpperSide) =
                    adapter.getLiquidityForAmounts(v.pool, amountsRemaining, v.fillUpTicksUpperSide);

                if (v.fillUpLiquidityLowerSide > v.fillUpLiquidityUpperSide) {
                    mintNewPositions[1].tickLower = v.fillUpTicksLowerSide[0];
                    mintNewPositions[1].tickUpper = v.fillUpTicksLowerSide[1];
                    mintNewPositions[1].liquidity = uint128(v.fillUpLiquidityLowerSide);
                    mintNewPositions[1].minAmount0 = v.fillUpAmountsConsumedLowerSide[0]
                        - (v.fillUpAmountsConsumedLowerSide[0] * slippage) / SLIPPAGE_PRECISION;
                    mintNewPositions[1].minAmount1 = v.fillUpAmountsConsumedLowerSide[1]
                        - (v.fillUpAmountsConsumedLowerSide[1] * slippage) / SLIPPAGE_PRECISION;
                } else {
                    mintNewPositions[1].tickLower = v.fillUpTicksUpperSide[0];
                    mintNewPositions[1].tickUpper = v.fillUpTicksUpperSide[1];
                    mintNewPositions[1].liquidity = uint128(v.fillUpLiquidityUpperSide);
                    mintNewPositions[1].minAmount0 = v.fillUpAmountsConsumedUpperSide[0]
                        - (v.fillUpAmountsConsumedUpperSide[0] * slippage) / SLIPPAGE_PRECISION;
                    mintNewPositions[1].minAmount1 = v.fillUpAmountsConsumedUpperSide[1]
                        - (v.fillUpAmountsConsumedUpperSide[1] * slippage) / SLIPPAGE_PRECISION;
                }
            }
        }
    }
}
