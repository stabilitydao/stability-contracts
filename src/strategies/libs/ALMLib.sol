// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IALM} from "../../interfaces/IALM.sol";
import {ILPStrategy} from "../../interfaces/ILPStrategy.sol";
import {IStrategy} from "../../interfaces/IStrategy.sol";
import {ICAmmAdapter} from "../../interfaces/ICAmmAdapter.sol";
import {AmmAdapterIdLib} from "../../adapters/libs/AmmAdapterIdLib.sol";
import {IUniswapV3Pool} from "../../integrations/uniswapv3/IUniswapV3Pool.sol";
import {UniswapV3MathLib} from "./UniswapV3MathLib.sol";

library ALMLib {
    uint public constant ALGO_FILL_UP = 0;

    uint public constant PRECISION = 1e36;

    function checkCompatibility(
        IALM.ALMStrategyBaseStorage storage $,
        ILPStrategy.LPStrategyBaseStorage storage _$_
    ) external view {
        ICAmmAdapter adapter = ICAmmAdapter(address(_$_.ammAdapter));
        if (keccak256(bytes(adapter.ammAdapterId())) != keccak256(bytes(AmmAdapterIdLib.UNISWAPV3))) {
            revert("Not supported CL AMM adapter");
        }
        if ($.algoId != ALGO_FILL_UP) {
            revert("Not supported ALM algo");
        }
    }

    function needRebalance(
        IALM.ALMStrategyBaseStorage storage $,
        ILPStrategy.LPStrategyBaseStorage storage _$_
    ) external view returns (bool need) {
        if ($.algoId == ALGO_FILL_UP) {
            uint len = $.positions.length;
            if (len == 0) {
                return false;
            }

            int24 halfRange = $.params[0] / 2;
            int24 halfTriggerRange = $.params[1] / 2;
            int24 oldMedianTick = $.positions[0].tickLower + halfRange;
            int24 currentTick = getUniswapV3CurrentTick(_$_.pool);
            return
                (currentTick > oldMedianTick + halfTriggerRange)
                || (currentTick < oldMedianTick - halfTriggerRange);
        }
    }

    function getAlgoNamyById(uint algoId) public pure returns(string memory) {
        if (algoId == ALGO_FILL_UP) {
            return "Fill-Up";
        }
        return "Unknown";
    }

    function getPresetNameByAlgoAndParams(uint algoId, int24[] memory params) public pure returns (string memory) {
        if (algoId == ALGO_FILL_UP) {
            if (params[0] >= 4000) {
                return "Passive";
            }
            if (params[0] >= 2000) {
                return "Wide";
            }
            if (params[0] >= 1000) {
                return "Narrow";
            }
            if (params[0] >= 100) {
                return "Aggressive";
            }
            return "Insane";
        }
        return "Unknown";
    }

    function preset(IALM.ALMStrategyBaseStorage storage $)
    external
    view
    returns (uint algoId, string memory algoName, string memory presetName, int24[] memory params) {
        algoId = $.algoId;
        algoName = getAlgoNamyById(algoId);
        params = $.params;
        presetName = getPresetNameByAlgoAndParams(algoId, params);
    }

    function assetsAmounts(
        IALM.ALMStrategyBaseStorage storage $,
        ILPStrategy.LPStrategyBaseStorage storage _$_,
        IStrategy.StrategyBaseStorage storage __$__
    ) external view returns (address[] memory assets_, uint[] memory amounts_) {
        ICAmmAdapter adapter = ICAmmAdapter(address(_$_.ammAdapter));
        address _pool = _$_.pool;
        assets_ = __$__._assets;
        amounts_ = new uint[](2);
        uint len = $.positions.length;
        for (uint i; i < len; ++i) {
            IALM.Position memory position = $.positions[i];
            int24[] memory ticks = new int24[](2);
            ticks[0] = position.tickLower;
            ticks[1] = position.tickUpper;
            uint[] memory positionAmounts = adapter.getAmountsForLiquidity(_pool, ticks, position.liquidity);
            amounts_[0] += positionAmounts[0];
            amounts_[1] += positionAmounts[1];
        }
    }

    function previewDepositAssets(
        uint[] memory amountsMax,
        IALM.ALMStrategyBaseStorage storage $,
        ILPStrategy.LPStrategyBaseStorage storage _$_,
        IStrategy.StrategyBaseStorage storage __$__
    ) external view returns (uint[] memory amountsConsumed, uint value) {
        if ($.algoId == ALGO_FILL_UP) {
            ICAmmAdapter adapter = ICAmmAdapter(address(_$_.ammAdapter));
            address pool = _$_.pool;
            uint price = getUniswapV3PoolPrice(pool);

            if (__$__.total == 0) {
                int24 tick = getUniswapV3CurrentTick(pool);
                int24[] memory ticks = new int24[](2);
                (ticks[0], ticks[1]) = calcFillUpBaseTicks(tick, $.params[0], getUniswapV3TickSpacing(pool));
                (, amountsConsumed) = adapter.getLiquidityForAmounts(pool, amountsMax, ticks);
                value = amountsConsumed[1] + (amountsConsumed[0] * price / PRECISION);
            } else {
                uint positionsLength = $.positions.length;
                int24[] memory ticks = new int24[](2);
                IALM.Position memory position = $.positions[0];
                ticks[0] = position.tickLower;
                ticks[1] = position.tickUpper;
                (, amountsConsumed) = adapter.getLiquidityForAmounts(pool, amountsMax, ticks);

                if (positionsLength == 2) {
                    uint[] memory amountsRemaining = new uint[](2);
                    amountsRemaining[0] = amountsMax[0] - amountsConsumed[0];
                    amountsRemaining[1] = amountsMax[1] - amountsConsumed[1];
                    position = $.positions[1];
                    ticks[0] = position.tickLower;
                    ticks[1] = position.tickUpper;
                    (, uint[] memory amountsConsumedFillUp) =
                        adapter.getLiquidityForAmounts(pool, amountsRemaining, ticks);
                    amountsConsumed[0] += amountsConsumedFillUp[0];
                    amountsConsumed[1] += amountsConsumedFillUp[1];
                }

                value = amountsConsumed[1] + (amountsConsumed[0] * price / PRECISION);

                (, uint[] memory totalAmounts) = IStrategy(address(this)).assetsAmounts();
                uint totalAmount = totalAmounts[1] + totalAmounts[0] * price / PRECISION;
                value = value * __$__.total / totalAmount;
            }
        }
    }

    function calcFillUpBaseTicks(
        int24 tick,
        int24 tickRange,
        int24 tickSpacing
    ) public pure returns (int24 lowerTick, int24 upperTick) {
        int24 halfTickRange = tickRange / 2;
        if (tick < 0 && tick / tickSpacing * tickSpacing != tick) {
            lowerTick = ((tick - halfTickRange) / tickSpacing - 1) * tickSpacing;
        } else {
            lowerTick = (tick - halfTickRange) / tickSpacing * tickSpacing;
        }
        upperTick = lowerTick + halfTickRange * 2;
    }

    function getUniswapV3PoolPrice(address pool) public view returns (uint price) {
        (uint160 sqrtPrice,,,,,,) = IUniswapV3Pool(pool).slot0();
        price = UniswapV3MathLib.mulDiv(uint(sqrtPrice) * uint(sqrtPrice), PRECISION, 2 ** (96 * 2));
    }

    function getUniswapV3TickSpacing(address pool) public view returns (int24 tickSpacing) {
        tickSpacing = IUniswapV3Pool(pool).tickSpacing();
    }

    function getUniswapV3CurrentTick(address pool) public view returns (int24 tick) {
        //slither-disable-next-line unused-return
        (, tick,,,,,) = IUniswapV3Pool(pool).slot0();
    }

    function balance(address token) public view returns (uint) {
        return IERC20(token).balanceOf(address(this));
    }
}
