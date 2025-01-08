// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import "../../chains/SonicLib.sol";
import "../base/UniversalTest.sol";
import {IGaugeV2_CL} from "../../src/integrations/swapx/IGaugeV2_CL.sol";
import {IVoterV3} from "../../src/integrations/swapx/IVoterV3.sol";

contract IchiSwapXFarmStrategyTest is SonicSetup, UniversalTest {
    constructor() {
        vm.rollFork(2927006); // Jan-08-2025 12:44:45 AM +UTC)
        skip(86400 * 2);

        depositedSharesCheckDelimiter = 10;
    }

    function testISF() public universalTest {
        _addStrategy(8);
        _addStrategy(9);
        _addStrategy(10);
        _addStrategy(11);
    }

    function _preHardWork() internal override {
        IGaugeV2_CL gauge = IGaugeV2_CL(IFarmingStrategy(currentStrategy).stakingPool());
        IVoterV3 voter = IVoterV3(gauge.DISTRIBUTION());
        address minter = voter.minter();
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);
        // uint rewardAmount = 1e18;
        // _deal(SonicLib.TOKEN_SWPx, minter, rewardAmount);
        vm.startPrank(minter);
        // IERC20(SonicLib.TOKEN_SWPx).approve(address(voter), type(uint).max);
        //  voter.notifyRewardAmount(rewardAmount);
        voter.distribute(gauges);
        vm.stopPrank();
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({id: StrategyIdLib.ICHI_SWAPX_FARM, pool: address(0), farmId: farmId, underlying: address(0)})
        );
    }
}
