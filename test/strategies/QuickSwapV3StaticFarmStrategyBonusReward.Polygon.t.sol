// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../base/chains/PolygonSetup.sol";
import "../base/UniversalTest.sol";
import "../../src/integrations/algebra/IAlgebraEternalFarming.sol";
import "../../src/interfaces/IFactory.sol";
import "../../src/interfaces/IPlatform.sol";
import {IncentiveKey} from "../../src/integrations/algebra/IncentiveKey.sol";

contract QuickSwapV3StaticFarmStrategyBonusReward is PolygonSetup, UniversalTest {
    address wmatic = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    address quick = address(0xB5C064F955D8e7F38fE0460C556a72987494eE17);
    address algebraEternalFarming = address(0x8a26436e41d0b5fc4C6Ed36C1976fafBe173444E);
    address farmingCenter = address(0x7F281A8cdF66eF5e9db8434Ec6D97acc1bc01E78);
    address pool = address(0xe7E0eB9F6bCcCfe847fDf62a3628319a092F11a2);

    function testStrategyUniversalP() public universalTest {
        strategies.push(
            Strategy({id: StrategyIdLib.QUICKSWAPV3_STATIC_FARM, pool: address(0), farmId: 0, underlying: address(0)})
        );
    }

    // function test_AddRewards() public {
    //     IFactory factory = IFactory(IPlatform(platform).factory());
    //     bytes32[] memory hashes = factory.strategyLogicIdHashes();

    //     IFactory.Farm memory farm = factory.farm(0);

    //     IAlgebraEternalFarming algebraFarming = IAlgebraEternalFarming(
    //         algebraEternalFarming
    //     );

    //     IncentiveKey memory key = IncentiveKey(
    //         farm.rewardAssets[0],
    //         farm.rewardAssets[1],
    //         farm.pool,
    //         farm.nums[0],
    //         farm.nums[1]
    //     );

    //     deal(farm.rewardAssets[1], address(this), 100e18);
    //     assertEq(IERC20(farm.rewardAssets[1]).balanceOf(address(this)), 100e18);
    //     IERC20(farm.rewardAssets[1]).approve(algebraEternalFarming, 10e18);
    //     assertEq(
    //         IERC20(farm.rewardAssets[1]).allowance(
    //             address(this),
    //             algebraEternalFarming
    //         ),
    //         10e18
    //     );

    //     algebraFarming.addRewards(key, 0, 10e18);
    // }
}
