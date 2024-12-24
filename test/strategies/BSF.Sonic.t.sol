// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import "../../chains/SonicLib.sol";
import "../base/UniversalTest.sol";
import "../../src/integrations/balancer/IBalancerGauge.sol";

contract BeetsStableFarmStrategyTest is SonicSetup, UniversalTest {
    function testBSF() public universalTest {
        _addStrategy(0);
    }

    /*function _preHardWork() internal override {
        address gauge = IFarmingStrategy(currentStrategy).stakingPool();
        S_0 memory s = IBalancerGauge(gauge).reward_data(SonicLib.TOKEN_BEETS);
        address distributor = s.distributor;
        _deal(SonicLib.TOKEN_BEETS, distributor, 1000e18);
        vm.startPrank(distributor);
        IERC20(SonicLib.TOKEN_BEETS).approve(gauge, type(uint).max);
        IBalancerGauge(gauge).deposit_reward_token(SonicLib.TOKEN_BEETS, 200e18);
        vm.stopPrank();
    }*/

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({id: StrategyIdLib.BEETS_STABLE_FARM, pool: address(0), farmId: farmId, underlying: address(0)})
        );
    }
}
