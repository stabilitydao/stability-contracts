// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/RealSetup.sol";
import "../base/UniversalTest.sol";
import {IVoter} from "../../src/integrations/pearl/IVoter.sol";

contract TridentPearlFarmStrategyTest is RealSetup, UniversalTest {
    address public constant VOTER = 0x4C44cFBBc35e68a31b693b3926F11a40abA5f93B;
    address public constant EPOCH_CONTROLLER = 0xA78f1A0193ac181fFc12a92425BFC697BD6705Ef;

    receive() external payable {}

    function testTPF() public universalTest {
        for (uint i; i < 12; ++i) {
            _addStrategy(i);
        }
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({id: StrategyIdLib.TRIDENT_PEARL_FARM, pool: address(0), farmId: farmId, underlying: address(0)})
        );
    }

    function _skip(uint time, uint farmId) internal override {
        IFactory.Farm memory farm = factory.farm(farmId);
        IGaugeV2CL gauge = IGaugeV2CL(farm.addresses[1]);

        if (gauge.periodFinish() < block.timestamp + time) {
            uint rewardsAmount = 10000e18;
            console.log("_skip: gauge rewards period ended, refilling rewards");
            _deal(RealLib.TOKEN_PEARL, VOTER, rewardsAmount);
            vm.startPrank(VOTER);
            IERC20(RealLib.TOKEN_PEARL).approve(address(gauge), rewardsAmount);
            gauge.notifyRewardAmount(RealLib.TOKEN_PEARL, rewardsAmount);
            vm.stopPrank();
            vm.prank(EPOCH_CONTROLLER);
            IVoter(VOTER).distributeAll();
        }

        skip(time);
    }
}
