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

    struct FillUpTicks {
        int24 lowerTickLower;
        int24 lowerTickUpper;
        int24 upperTickLower;
        int24 upperTickUpper;
    }

    struct FillUpParams {
        int24 currentTick;
        int24 tickSpacing;
        uint[] remainingAmounts;
        uint slippage;
        ICAmmAdapter adapter;
        address pool;
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
        v.pool = ILPStrategy(strategy).pool();
        v.tickSpacing = ALMLib.getUniswapV3TickSpacing(v.pool);
        v.currentTick = ALMLib.getUniswapV3CurrentTick(v.pool);
        ICAmmAdapter adapter = ICAmmAdapter(address(ILPStrategy(strategy).ammAdapter()));
        (, v.amounts) = IStrategy(strategy).assetsAmounts();

        // Retrieve strategy preset and positions
        (v.algoId,,, v.params) = IALM(strategy).preset();
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

                mintNewPositions = _createSingleBasePosition(
                    oldBasePosition, v.currentTick, v.tickSpacing, adapter, v.pool, v.amounts, slippage
                );
            } else {
                // Mark only non-base positions for burning
                for (uint i = 0; i < positionsLength; i++) {
                    burnOldPositions[i] = true;
                }

                mintNewPositions = _createBaseAndFillUpPositions(
                    v.currentTick, v.params[0], v.tickSpacing, adapter, v.pool, v.amounts, slippage
                );
            }
        }
    }

    /// @dev Creates a single base position when the current tick is out of range.
    /// @param oldBasePosition The existing base position.
    /// @param currentTick The current tick.
    /// @param tickSpacing The tick spacing of the pool.
    /// @param adapter The AMM adapter.
    /// @param pool The pool address.
    /// @param amounts The asset amounts.
    /// @param slippage The slippage tolerance.
    /// @return mintNewPositions Array containing the new base position.
    function _createSingleBasePosition(
        IALM.Position memory oldBasePosition,
        int24 currentTick,
        int24 tickSpacing,
        ICAmmAdapter adapter,
        address pool,
        uint[] memory amounts,
        uint slippage
    ) internal view returns (IALM.NewPosition[] memory mintNewPositions) {
        mintNewPositions = new IALM.NewPosition[](1);

        int24 tickDistance;

        if (currentTick > oldBasePosition.tickUpper) {
            tickDistance = (currentTick - oldBasePosition.tickUpper) / tickSpacing * tickSpacing;
            mintNewPositions[0].tickLower = oldBasePosition.tickLower + tickDistance;
            mintNewPositions[0].tickUpper = oldBasePosition.tickUpper + tickDistance;
        } else {
            tickDistance = (oldBasePosition.tickLower - currentTick) / tickSpacing * tickSpacing;
            mintNewPositions[0].tickLower = oldBasePosition.tickLower - tickDistance;
            mintNewPositions[0].tickUpper = oldBasePosition.tickUpper - tickDistance;
        }

        if (tickDistance == 0) {
            revert IALM.CantDoRebalance();
        }

        int24[] memory ticks = new int24[](2);
        ticks[0] = mintNewPositions[0].tickLower;
        ticks[1] = mintNewPositions[0].tickUpper;

        (uint addedLiquidity, uint[] memory amountsConsumed) = adapter.getLiquidityForAmounts(pool, amounts, ticks);

        mintNewPositions[0].liquidity = uint128(addedLiquidity);
        mintNewPositions[0].minAmount0 = amountsConsumed[0] - (amountsConsumed[0] * slippage) / SLIPPAGE_PRECISION;
        mintNewPositions[0].minAmount1 = amountsConsumed[1] - (amountsConsumed[1] * slippage) / SLIPPAGE_PRECISION;

        return mintNewPositions;
    }

    /// @dev Creates a base position and fill-up position when the current tick is within range.
    /// @param currentTick The current tick.
    /// @param baseRangeWidth The width of the base range.
    /// @param tickSpacing The tick spacing of the pool.
    /// @param adapter The AMM adapter.
    /// @param pool The pool address.
    /// @param amounts The asset amounts.
    /// @param slippage The slippage tolerance.
    /// @return mintNewPositions Array containing the base and fill-up positions.
    function _createBaseAndFillUpPositions(
        int24 currentTick,
        int24 baseRangeWidth,
        int24 tickSpacing,
        ICAmmAdapter adapter,
        address pool,
        uint[] memory amounts,
        uint slippage
    ) internal view returns (IALM.NewPosition[] memory mintNewPositions) {
        mintNewPositions = new IALM.NewPosition[](2);

        // Calculate base position ticks
        (mintNewPositions[0].tickLower, mintNewPositions[0].tickUpper) =
            ALMLib.calcFillUpBaseTicks(currentTick, baseRangeWidth, tickSpacing);

        int24[] memory baseTicks = new int24[](2);
        baseTicks[0] = mintNewPositions[0].tickLower;
        baseTicks[1] = mintNewPositions[0].tickUpper;

        // Calculate liquidity and consumed amounts for base position
        (uint addedLiquidity, uint[] memory amountsConsumed) = adapter.getLiquidityForAmounts(pool, amounts, baseTicks);

        mintNewPositions[0].liquidity = uint128(addedLiquidity);
        mintNewPositions[0].minAmount0 = amountsConsumed[0] - (amountsConsumed[0] * slippage) / SLIPPAGE_PRECISION;
        mintNewPositions[0].minAmount1 = amountsConsumed[1] - (amountsConsumed[1] * slippage) / SLIPPAGE_PRECISION;

        // Calculate remaining asset amounts for fill-up position
        uint[] memory remainingAmounts = new uint[](2);
        remainingAmounts[0] = amounts[0] - amountsConsumed[0];
        remainingAmounts[1] = amounts[1] - amountsConsumed[1];

        // Prepare parameters for fill-up ticks and liquidity comparison
        FillUpParams memory params = FillUpParams({
            currentTick: currentTick,
            tickSpacing: tickSpacing,
            remainingAmounts: remainingAmounts,
            slippage: slippage,
            adapter: adapter,
            pool: pool
        });

        // Select the better fill-up position
        mintNewPositions[1] = _selectBestFillUpPosition(params);

        return mintNewPositions;
    }

    /// @dev Helper function to select the best fill-up position based on liquidity.
    function _selectBestFillUpPosition(FillUpParams memory params)
        internal
        view
        returns (IALM.NewPosition memory bestPosition)
    {
        // Calculate fill-up ticks on both sides of the current price
        int24 lowerTickLower = params.currentTick > 0
            ? (params.currentTick / params.tickSpacing * params.tickSpacing)
            : ((params.currentTick / params.tickSpacing * params.tickSpacing) - params.tickSpacing);

        int24 lowerTickUpper = lowerTickLower + params.tickSpacing;

        int24 upperTickLower = lowerTickUpper;

        int24 upperTickUpper = upperTickLower + params.tickSpacing;

        // Prepare tick arrays for liquidity comparison
        int24[] memory lowerFillUpTicks = new int24[](2);
        lowerFillUpTicks[0] = lowerTickLower;
        lowerFillUpTicks[1] = lowerTickUpper;

        int24[] memory upperFillUpTicks = new int24[](2);
        upperFillUpTicks[0] = upperTickLower;
        upperFillUpTicks[1] = upperTickUpper;

        // Compare liquidity for both sides
        (uint lowerLiquidity, uint[] memory lowerAmountsConsumed) =
            params.adapter.getLiquidityForAmounts(params.pool, params.remainingAmounts, lowerFillUpTicks);

        (uint upperLiquidity, uint[] memory upperAmountsConsumed) =
            params.adapter.getLiquidityForAmounts(params.pool, params.remainingAmounts, upperFillUpTicks);

        if (lowerLiquidity > upperLiquidity) {
            bestPosition.tickLower = lowerFillUpTicks[0];
            bestPosition.tickUpper = lowerFillUpTicks[1];
            bestPosition.liquidity = uint128(lowerLiquidity);
            bestPosition.minAmount0 =
                lowerAmountsConsumed[0] - (lowerAmountsConsumed[0] * params.slippage) / SLIPPAGE_PRECISION;
            bestPosition.minAmount1 =
                lowerAmountsConsumed[1] - (lowerAmountsConsumed[1] * params.slippage) / SLIPPAGE_PRECISION;
        } else {
            bestPosition.tickLower = upperFillUpTicks[0];
            bestPosition.tickUpper = upperFillUpTicks[1];
            bestPosition.liquidity = uint128(upperLiquidity);
            bestPosition.minAmount0 =
                upperAmountsConsumed[0] - (upperAmountsConsumed[0] * params.slippage) / SLIPPAGE_PRECISION;
            bestPosition.minAmount1 =
                upperAmountsConsumed[1] - (upperAmountsConsumed[1] * params.slippage) / SLIPPAGE_PRECISION;
        }

        return bestPosition;
    }
}
