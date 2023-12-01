// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../base/chains/PolygonSetup.sol";
import "../base/UniversalTest.sol";
import "../../src/integrations/algebra/IAlgebraEternalFarming.sol";
import "../../src/interfaces/IFactory.sol";
import "../../src/interfaces/IPlatform.sol";

import {QuickSwapV3StaticFarmStrategy} from "../../src/strategies/QuickswapV3StaticFarmStrategy.sol";

contract QuickSwapV3StaticFarmStrategyBonusReward is PolygonSetup, UniversalTest {
    QuickSwapV3StaticFarmStrategy public qsStrategy;

    function setUp() public {
        
    }

    function testStrategyUniversal() public universalTest {
        address[2] memory addresses;
        addresses[0] = address(0x8eF88E4c7CfbbaC1C163f7eddd4B578792201de6);
        addresses[1] = address(0x7F281A8cdF66eF5e9db8434Ec6D97acc1bc01E78);

        IFactory.Farm memory farm = IFactory(IPlatform(platform).factory()).farm(0);
        qsStrategy = new QuickSwapV3StaticFarmStrategy();

        strategies.push(
            Strategy({
                id: StrategyIdLib.QUICKSWAPV3_STATIC_FARM,
                pool: address(0),
                farmId: 0, // chains/PolygonLib.sol
                underlying: address(0)
            })
        );

        address wmatic = address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
        address quick = address(0xB5C064F955D8e7F38fE0460C556a72987494eE17);
        address algebraEternalFarming = address(
            0x8a26436e41d0b5fc4C6Ed36C1976fafBe173444E
        );
        address pool = address(0xe7E0eB9F6bCcCfe847fDf62a3628319a092F11a2);

        deal(wmatic, address(this), 10000e18);
        assertEq(IERC20(wmatic).balanceOf(address(this)), 10000e18);

        IAlgebraEternalFarming algebraFarming = IAlgebraEternalFarming(
            algebraEternalFarming
        );

        IncentiveKey memory key = qsStrategy.getIncentiveKey();

        // farming.addRewards(key, 10e18, 10e18);
        // farming.getRewardInfo(incentiveKey, )
    }
}
