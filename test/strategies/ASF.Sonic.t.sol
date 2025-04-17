// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import "../../chains/sonic/SonicLib.sol";
import "../base/UniversalTest.sol";
import {RebalanceHelper} from "../../src/periphery/RebalanceHelper.sol";

contract ALMShadowFarmStrategyTest is SonicSetup, UniversalTest {
    RebalanceHelper public rebalanceHelper;

    constructor() {
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.5 hours;

        makePoolVolumePriceImpactTolerance = 34_000;
        poolVolumeSwapAmount0MultiplierForPool[SonicConstantsLib.POOL_SHADOW_CL_wS_WETH] = 500; // 500k
        poolVolumeSwapAmount1MultiplierForPool[SonicConstantsLib.POOL_SHADOW_CL_wS_WETH] = 650; // 650k
        poolVolumeSwapAmount0MultiplierForPool[SonicConstantsLib.POOL_SHADOW_CL_wS_BRUSH_5000] = 800;
        poolVolumeSwapAmount1MultiplierForPool[SonicConstantsLib.POOL_SHADOW_CL_wS_BRUSH_5000] = 400;

        rebalanceHelper = new RebalanceHelper();
    }

    function testASF() public universalTest {
        _addStrategy(25); // wS_WETH 3000
        _addStrategy(26); // wS_WETH 1500
        _addStrategy(27); // wS_USDC 3000
        _addStrategy(28); // wS_USDC 1500
        _addStrategy(29);
        _addStrategy(30);
    }

    function _rebalance() internal override {
        if (IALM(currentStrategy).needRebalance()) {
            /*console.log('Need re-balance call');
            IALM.Position[] memory positions = IALM(currentStrategy).positions();
            console.log("Old base position (ticks, liquidity):");
            console.logInt(positions[0].tickLower);
            console.logInt(positions[0].tickUpper);
            console.log(positions[0].liquidity);
            if (positions.length == 2) {
                console.log("Old flup position (ticks, liquidity):");
                console.logInt(positions[1].tickLower);
                console.logInt(positions[1].tickUpper);
                console.log(positions[1].liquidity);
            }*/

            (bool[] memory burnOldPositions, IALM.NewPosition[] memory mintNewPositions) =
                rebalanceHelper.calcRebalanceArgs(currentStrategy, 10);
            IALM(currentStrategy).rebalance(burnOldPositions, mintNewPositions);

            /*
            positions = IALM(currentStrategy).positions();
            console.log('Re-balance done. New tick:');
            console.logInt(ALMLib.getUniswapV3CurrentTick(ILPStrategy(currentStrategy).pool()));
            console.log("New base position (ticks, liquidity):");
            console.logInt(positions[0].tickLower);
            console.logInt(positions[0].tickUpper);
            console.log(positions[0].liquidity);
            if (positions.length == 2) {
                console.log("New flup position (ticks, liquidity):");
                console.logInt(positions[1].tickLower);
                console.logInt(positions[1].tickUpper);
                console.log(positions[1].liquidity);
            }*/

            rebalanceHelper.VERSION();
        }
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.ALM_SHADOW_FARM,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }
}
