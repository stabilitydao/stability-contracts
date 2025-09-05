// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// import {console} from "forge-std/Test.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {SonicConstantsLib, StrategyIdLib} from "../../chains/sonic/SonicLib.sol";
import {UniversalTest} from "../base/UniversalTest.sol";
import {IBalancerGauge} from "../../src/integrations/balancer/IBalancerGauge.sol";

contract BeetsStableFarmStrategyTest is SonicSetup, UniversalTest {
    function testBSF() public universalTest {
        _addStrategy(0);
        //_addStrategy(1);
    }

    /*function _preHardWork() internal override {
        address gauge = IFarmingStrategy(currentStrategy).stakingPool();
        S_0 memory s = IBalancerGauge(gauge).reward_data(SonicConstantsLib.TOKEN_BEETS);
        address distributor = s.distributor;
        _deal(SonicConstantsLib.TOKEN_BEETS, distributor, 1000e18);
        vm.startPrank(distributor);
        IERC20(SonicConstantsLib.TOKEN_BEETS).approve(gauge, type(uint).max);
        IBalancerGauge(gauge).deposit_reward_token(SonicConstantsLib.TOKEN_BEETS, 200e18);
        vm.stopPrank();
    }*/

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.BEETS_STABLE_FARM,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }
}
