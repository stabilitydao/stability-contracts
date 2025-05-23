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
///   1.1.0: calcRebalanceArgs utilize burnOldPositions for fill-up positions
///   1.0.2: calcRebalanceArgs bugfix
///   1.0.1: calcRebalanceArgs bugfix
/// @author Alien Deployer (https://github.com/a17)
/// @author 0xalpha0123 (https://github.com/0xalpha0123)
contract RebalanceHelper {
    string public constant VERSION = "1.1.0";
    uint internal constant SLIPPAGE_PRECISION = 100_000;

    struct CalcRebalanceVars {
        uint algoId;
        int24[] params;
        address pool;
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

        uint positionsLength = IALM(strategy).positions().length;
        burnOldPositions = new bool[](positionsLength); // Initialize burnOldPositions array
        for (uint i = 0; i < positionsLength; i++) {
            burnOldPositions[i] = false;
        }
        // Retrieve strategy preset and positions
        // slither-disable-next-line unused-return
        (v.algoId,,, v.params) = IALM(strategy).preset();
        v.pool = ILPStrategy(strategy).pool();
        ICAmmAdapter adapter = ICAmmAdapter(address(ILPStrategy(strategy).ammAdapter()));
        int24 tick = ALMLib.getUniswapV3CurrentTick(v.pool);
        int24 tickSpacing = ALMLib.getUniswapV3TickSpacing(v.pool);
        // slither-disable-next-line unused-return
        (, uint[] memory amounts) = IStrategy(strategy).assetsAmounts();
        int24[] memory ticks = new int24[](2);

        // Handle ALGO_FILL_UP logic
        if (v.algoId == ALMLib.ALGO_FILL_UP) {
            // check if out of range
            IALM.Position memory oldBasePosition = IALM(strategy).positions()[0];
            // Determine if base position needs rebalancing
            if (tick > oldBasePosition.tickUpper || tick < oldBasePosition.tickLower) {
                // out of range: 1 new position with single asset
                mintNewPositions = new IALM.NewPosition[](1);
                burnOldPositions[0] = true;
                if (tick > oldBasePosition.tickUpper) {
                    int24 tickDistance = tick - oldBasePosition.tickUpper;
                    //slither-disable-next-line divide-before-multiply
                    tickDistance = tickDistance / tickSpacing * tickSpacing;
                    if (tickDistance == 0) {
                        revert IALM.CantDoRebalance();
                    }
                    mintNewPositions[0].tickLower = oldBasePosition.tickLower + tickDistance;
                    mintNewPositions[0].tickUpper = oldBasePosition.tickUpper + tickDistance;
                } else {
                    int24 tickDistance = oldBasePosition.tickLower - tick;
                    //slither-disable-next-line divide-before-multiply
                    tickDistance = tickDistance / tickSpacing * tickSpacing;
                    if (tickDistance == 0) {
                        revert IALM.CantDoRebalance();
                    }
                    mintNewPositions[0].tickLower = oldBasePosition.tickLower - tickDistance;
                    mintNewPositions[0].tickUpper = oldBasePosition.tickUpper - tickDistance;
                }

                ticks[0] = mintNewPositions[0].tickLower;
                ticks[1] = mintNewPositions[0].tickUpper;
                // slither-disable-next-line unused-return
                (uint addedLiquidity, uint[] memory amountsConsumed) =
                    adapter.getLiquidityForAmounts(v.pool, amounts, ticks);
                mintNewPositions[0].liquidity = uint128(addedLiquidity);
                mintNewPositions[0].minAmount0 = amountsConsumed[0] - amountsConsumed[0] * slippage / SLIPPAGE_PRECISION;
                mintNewPositions[0].minAmount1 = amountsConsumed[1] - amountsConsumed[1] * slippage / SLIPPAGE_PRECISION;
            } else {
                // 2 new positions
                mintNewPositions = new IALM.NewPosition[](2);
                if (burnOldPositions.length > 0) burnOldPositions[0] = true;
                if (burnOldPositions.length > 1) burnOldPositions[1] = true;
                (mintNewPositions[0].tickLower, mintNewPositions[0].tickUpper) =
                    ALMLib.calcFillUpBaseTicks(tick, v.params[0], tickSpacing);

                // calc new base position liquidity and amounts
                ticks[0] = mintNewPositions[0].tickLower;
                ticks[1] = mintNewPositions[0].tickUpper;
                (uint addedLiquidity, uint[] memory amountsConsumed) =
                    adapter.getLiquidityForAmounts(v.pool, amounts, ticks);
                mintNewPositions[0].liquidity = uint128(addedLiquidity);
                mintNewPositions[0].minAmount0 = amountsConsumed[0] - amountsConsumed[0] * slippage / SLIPPAGE_PRECISION;
                mintNewPositions[0].minAmount1 = amountsConsumed[1] - amountsConsumed[1] * slippage / SLIPPAGE_PRECISION;

                // Calculate remaining asset amounts for fill-up position
                uint[] memory amountsRemaining = new uint[](2);
                amountsRemaining[0] = amounts[0] - amountsConsumed[0];
                amountsRemaining[1] = amounts[1] - amountsConsumed[1];
                //bool intDiv = tick / tickSpacing * tickSpacing == tick;

                // Calculate fill-up ticks on both sides of the current price
                v.fillUpTicksLowerSide = new int24[](2);
                v.fillUpTicksLowerSide[0] = mintNewPositions[0].tickLower;
                //slither-disable-next-line divide-before-multiply
                v.fillUpTicksLowerSide[1] =
                    tick > 0 ? (tick / tickSpacing * tickSpacing) : (tick / tickSpacing * tickSpacing - tickSpacing);
                v.fillUpTicksUpperSide = new int24[](2);
                //slither-disable-next-line divide-before-multiply
                v.fillUpTicksUpperSide[0] =
                    tick > 0 ? (tick / tickSpacing * tickSpacing + tickSpacing) : (tick / tickSpacing * tickSpacing);
                v.fillUpTicksUpperSide[1] = mintNewPositions[0].tickUpper;

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
                        - v.fillUpAmountsConsumedLowerSide[0] * slippage / SLIPPAGE_PRECISION;
                    mintNewPositions[1].minAmount1 = v.fillUpAmountsConsumedLowerSide[1]
                        - v.fillUpAmountsConsumedLowerSide[1] * slippage / SLIPPAGE_PRECISION;
                } else {
                    mintNewPositions[1].tickLower = v.fillUpTicksUpperSide[0];
                    mintNewPositions[1].tickUpper = v.fillUpTicksUpperSide[1];
                    mintNewPositions[1].liquidity = uint128(v.fillUpLiquidityUpperSide);
                    mintNewPositions[1].minAmount0 = v.fillUpAmountsConsumedUpperSide[0]
                        - v.fillUpAmountsConsumedUpperSide[0] * slippage / SLIPPAGE_PRECISION;
                    mintNewPositions[1].minAmount1 = v.fillUpAmountsConsumedUpperSide[1]
                        - v.fillUpAmountsConsumedUpperSide[1] * slippage / SLIPPAGE_PRECISION;
                }
            }
        }
    }
}
