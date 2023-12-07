// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../base/UniversalTest.sol";
import "../base/chains/PolygonSetup.sol";
import "../../src/interfaces/IFactory.sol";
import "../../src/interfaces/IPlatform.sol";
import "../../src/interfaces/IVault.sol";
import "../../src/integrations/algebra/IAlgebraEternalFarming.sol";
import "../../src/integrations/algebra/IAlgebraEternalVirtualPool.sol";

import {IncentiveKey} from "../../src/integrations/algebra/IncentiveKey.sol";

contract QuickSwapV3StaticFarmStrategyBonusReward is PolygonSetup, UniversalTest {
    address algebraEternalFarming = address(0x8a26436e41d0b5fc4C6Ed36C1976fafBe173444E);
    address virtualPool = address(0x1601bA8e8E25366561b2dA7B09F32F57b216c0bD);

    function testStrategyUniversalP() public universalTest {
        strategies.push(
            Strategy({id: StrategyIdLib.QUICKSWAPV3_STATIC_FARM, pool: address(0), farmId: 0, underlying: address(0)})
        );
    }

    function test_AddRewards(Platform platform) internal virtual override {
        IFactory.Farm memory farm = IFactory(IPlatform(platform).factory()).farm(0);
        IncentiveKey memory key =
            IncentiveKey(farm.rewardAssets[0], farm.rewardAssets[1], farm.pool, farm.nums[0], farm.nums[1]);
        
        IAlgebraEternalFarming algebraFarming = IAlgebraEternalFarming(algebraEternalFarming);
        deal(farm.rewardAssets[1], address(this), 100e18);
        assertEq(IERC20(farm.rewardAssets[1]).balanceOf(address(this)), 100e18);

        IERC20(farm.rewardAssets[1]).approve(algebraEternalFarming, 10e18);
        assertEq(IERC20(farm.rewardAssets[1]).allowance(address(this), algebraEternalFarming), 10e18);

        vm.startPrank(algebraEternalFarming);
        IAlgebraEternalVirtualPool(virtualPool).addRewards(0, 10e18);
        IAlgebraEternalVirtualPool(virtualPool).setRates(1106846000000000000000000, 100000000000000);
        vm.stopPrank();
    }

    function test_Deposit(address vault, address assets0, address asset1) internal virtual override {
        uint[] memory depAssets = new uint[](2);
        address[] memory assets = new address[](2);

        depAssets[0] = 2000e18;
        depAssets[1] = 2000e18;
        assets[0] = assets0;
        assets[1] = asset1;

        deal(assets[0], address(this), depAssets[0]);
        deal(assets[1], address(this), depAssets[1]);
        IERC20(assets[0]).approve(vault, depAssets[0]);
        IERC20(assets[1]).approve(vault, depAssets[1]);
        IVault(vault).depositAssets(assets, depAssets, 0, address(0));
    }
}
