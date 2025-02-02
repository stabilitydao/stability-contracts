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
///   1.0.1: calcRebalanceArgs bugfix
/// @author Alien Deployer (https://github.com/a17)
contract RebalanceHelper {
    string public constant VERSION = "1.0.1";
    uint internal constant SLIPPAGE_PRECISION = 100_000;

    /// @notice Calculate new position arguments for ALM re-balancing
    /// @param strategy Address of ALM strategy
    /// @param slippage Slippage check. 50_000 - 50%, 1_000 - 1%, 100 - 0.1%, 1 - 0.001%
    /// @return burnOldPositions Burn old positions or not. Zero length mean burn all.
    /// @return mintNewPositions New positions data
    function calcRebalanceArgs(
        address strategy,
        uint slippage
    ) external view returns (bool[] memory burnOldPositions, IALM.NewPosition[] memory mintNewPositions) {
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
                (uint addedLiquidity, uint[] memory amountsConsumed) =
                    adapter.getLiquidityForAmounts(pool, amounts, ticks);
                mintNewPositions[0].liquidity = uint128(addedLiquidity);
                mintNewPositions[0].minAmount0 = amountsConsumed[0] - amountsConsumed[0] * slippage / SLIPPAGE_PRECISION;
                mintNewPositions[0].minAmount1 = amountsConsumed[1] - amountsConsumed[1] * slippage / SLIPPAGE_PRECISION;
            } else {
                // 2 new positions
                mintNewPositions = new IALM.NewPosition[](2);
                (mintNewPositions[0].tickLower, mintNewPositions[0].tickUpper) =
                    ALMLib.calcFillUpBaseTicks(tick, params[0], tickSpacing);

                // calc new base position liquidity and amounts
                ticks[0] = mintNewPositions[0].tickLower;
                ticks[1] = mintNewPositions[0].tickUpper;
                (uint addedLiquidity, uint[] memory amountsConsumed) =
                    adapter.getLiquidityForAmounts(pool, amounts, ticks);
                mintNewPositions[0].liquidity = uint128(addedLiquidity);
                mintNewPositions[0].minAmount0 = amountsConsumed[0] - amountsConsumed[0] * slippage / SLIPPAGE_PRECISION;
                mintNewPositions[0].minAmount1 = amountsConsumed[1] - amountsConsumed[1] * slippage / SLIPPAGE_PRECISION;

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
                mintNewPositions[1].minAmount0 = amountsConsumed[0] - amountsConsumed[0] * slippage / SLIPPAGE_PRECISION;
                mintNewPositions[1].minAmount1 = amountsConsumed[1] - amountsConsumed[1] * slippage / SLIPPAGE_PRECISION;
            }
        }
    }
}
