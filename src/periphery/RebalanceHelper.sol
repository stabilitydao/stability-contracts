// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IALM} from "../interfaces/IALM.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {ILPStrategy} from "../interfaces/ILPStrategy.sol";
import {ICAmmAdapter} from "../interfaces/ICAmmAdapter.sol";
import {ALMLib} from "../strategies/libs/ALMLib.sol";

contract RebalanceHelper {
    function calcRebalanceArgs(address strategy)
        external
        view
        returns (bool[] memory burnOldPositions, IALM.NewPosition[] memory mintNewPositions)
    {
        if (!IERC165(strategy).supportsInterface(type(IALM).interfaceId)) {
            revert IALM.NotALM();
        }

        if (!IALM(strategy).needRebalance()) {
            revert IALM.NotNeedRebalance();
        }

        burnOldPositions = new bool[](0);
        // slither-disable-next-line unused-return
        (uint algoId,,, int24[] memory params) = IALM(strategy).preset();
        address pool = ILPStrategy(strategy).pool();
        ICAmmAdapter adapter = ICAmmAdapter(address(ILPStrategy(strategy).ammAdapter()));
        int24 tick = ALMLib.getUniswapV3CurrentTick(pool);
        int24 tickSpacing = ALMLib.getUniswapV3TickSpacing(pool);
        // slither-disable-next-line unused-return
        (, uint[] memory amounts) = IStrategy(strategy).assetsAmounts();
        int24[] memory ticks = new int24[](2);

        if (algoId == ALMLib.ALGO_FILL_UP) {
            // check if out of range
            IALM.Position memory oldBasePosition = IALM(strategy).positions()[0];
            if (tick > oldBasePosition.tickUpper || tick < oldBasePosition.tickLower) {
                // out of range: 1 new position with single asset
                mintNewPositions = new IALM.NewPosition[](1);
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
                (uint addedLiquidity, /*uint[] memory amountsConsumed*/ ) =
                    adapter.getLiquidityForAmounts(pool, amounts, ticks);
                mintNewPositions[0].liquidity = uint128(addedLiquidity);
                // todo slippage
            } else {
                // 2 new positions
                mintNewPositions = new IALM.NewPosition[](2);
                (mintNewPositions[0].tickLower, mintNewPositions[0].tickUpper) =
                    ALMLib.calcFillUpBaseTicks(tick, params[0], params[1]);

                // calc new base position liquidity and amounts
                ticks[0] = mintNewPositions[0].tickLower;
                ticks[1] = mintNewPositions[0].tickUpper;
                (uint addedLiquidity, uint[] memory amountsConsumed) =
                    adapter.getLiquidityForAmounts(pool, amounts, ticks);
                mintNewPositions[0].liquidity = uint128(addedLiquidity);
                // todo slippage

                // calc fill-up
                uint[] memory amountsRemaining = new uint[](2);
                amountsRemaining[0] = amounts[0] - amountsConsumed[0];
                amountsRemaining[1] = amounts[1] - amountsConsumed[1];
                if (mintNewPositions[0].tickLower > oldBasePosition.tickLower) {
                    mintNewPositions[1].tickLower = mintNewPositions[0].tickLower;
                    //slither-disable-next-line divide-before-multiply
                    mintNewPositions[1].tickUpper =
                        tick > 0 ? (tick / tickSpacing * tickSpacing) : (tick / tickSpacing * tickSpacing - tickSpacing);
                } else {
                    //slither-disable-next-line divide-before-multiply
                    mintNewPositions[1].tickLower =
                        tick > 0 ? (tick / tickSpacing * tickSpacing + tickSpacing) : (tick / tickSpacing * tickSpacing);
                    mintNewPositions[1].tickUpper = mintNewPositions[0].tickUpper;
                }
                ticks[0] = mintNewPositions[1].tickLower;
                ticks[1] = mintNewPositions[1].tickUpper;
                (addedLiquidity, amountsConsumed) = adapter.getLiquidityForAmounts(pool, amountsRemaining, ticks);
                mintNewPositions[1].liquidity = uint128(addedLiquidity);
                // todo slippage
            }
        }
    }
}
