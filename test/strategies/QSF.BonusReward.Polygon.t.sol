// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/UniversalTest.sol";
import "../base/chains/PolygonSetup.sol";
import "../../src/interfaces/IFactory.sol";
import "../../src/interfaces/IPlatform.sol";
import "../../src/interfaces/IVault.sol";
import "../../src/integrations/algebra/IAlgebraEternalFarming.sol";
import "../../src/integrations/algebra/IAlgebraEternalVirtualPool.sol";

contract QuickSwapV3StaticFarmStrategyBonusRewardTest is PolygonSetup, UniversalTest {
    address algebraEternalFarming = address(0x8a26436e41d0b5fc4C6Ed36C1976fafBe173444E);
    address virtualPool = address(0x1601bA8e8E25366561b2dA7B09F32F57b216c0bD);

    function testStrategyUniversalP() public universalTest {
        strategies.push(
            Strategy({id: StrategyIdLib.QUICKSWAPV3_STATIC_FARM, pool: address(0), farmId: 0, underlying: address(0)})
        );
    }

    function _addRewards(uint farmId) internal virtual override {
        if (farmId == 0) {
            IFactory.Farm memory farm = IFactory(IPlatform(platform).factory()).farm(0);

            deal(farm.rewardAssets[1], address(this), 100e18);
            assertEq(IERC20(farm.rewardAssets[1]).balanceOf(address(this)), 100e18);

            IERC20(farm.rewardAssets[1]).approve(algebraEternalFarming, 10e18);
            assertEq(IERC20(farm.rewardAssets[1]).allowance(address(this), algebraEternalFarming), 10e18);

            vm.startPrank(algebraEternalFarming);
            IAlgebraEternalVirtualPool(virtualPool).addRewards(0, 10e18);
            IAlgebraEternalVirtualPool(virtualPool).setRates(1106846000000000000000000, 100000000000000);
            vm.stopPrank();
        }
    }
}
