// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/Test.sol";
import {RealSetup, RealLib} from "../base/chains/RealSetup.sol";
import {UniversalTest, StrategyIdLib, IFactory} from "../base/UniversalTest.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {IVoter} from "../../src/integrations/pearl/IVoter.sol";
import {IGaugeV2CL} from "../../src/integrations/pearl/IGaugeV2CL.sol";
// import "../base/UniversalTest.sol";
// import "../base/chains/RealSetup.sol";

// todo: replace Real-logic by Sonic-logic
contract TridentPearlFarmStrategyTest is SonicSetup, /* RealSetup */ UniversalTest {
    address public constant VOTER = 0x4C44cFBBc35e68a31b693b3926F11a40abA5f93B;
    address public constant EPOCH_CONTROLLER = 0xA78f1A0193ac181fFc12a92425BFC697BD6705Ef;

    receive() external payable {}

    function _testTPF() internal /*universalTest*/ {
        for (uint i; i < 12; ++i) {
            _addStrategy(i);
        }
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.TRIDENT_PEARL_FARM,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
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
