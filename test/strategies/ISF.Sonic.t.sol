// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";

contract IchiSwapXFarmStrategyTest is SonicSetup, UniversalTest {
    constructor() {
        allowZeroApr = true;
        vm.rollFork(19058000); // Apr-09-2025 02:20:57 AM +UTC

        /*vm.rollFork(2975061); // Jan-08-2025 11:28:28 AM +UTC
        skip(86400);
        depositedSharesCheckDelimiter = 10;
        // prevent emergencystop revert for empty Ichi ALMs
        _deal(SonicConstantsLib.TOKEN_WS, address(1), 20e18);
        _deal(SonicConstantsLib.TOKEN_SACRA_GEM_1, address(1), 20e18);
        vm.startPrank(address(1));
        IERC20(SonicConstantsLib.TOKEN_WS).approve(SonicConstantsLib.ALM_ICHI_SWAPX_WS_SACRA_GEM_1, type(uint).max);
        IERC20(SonicConstantsLib.TOKEN_SACRA_GEM_1).approve(SonicConstantsLib.ALM_ICHI_SWAPX_SACRA_GEM_1_WS, type(uint).max);
        IICHIVaultV4(SonicConstantsLib.ALM_ICHI_SWAPX_WS_SACRA_GEM_1).deposit(20e18, 0, address(1));
        IICHIVaultV4(SonicConstantsLib.ALM_ICHI_SWAPX_SACRA_GEM_1_WS).deposit(0, 20e18, address(1));
        vm.stopPrank();*/
    }

    function testISF() public universalTest {
        //        _addStrategy(8);
        //        _addStrategy(9);
        //        _addStrategy(10);
        //        _addStrategy(11);
        //        _addStrategy(12);
        //        _addStrategy(13);
        _addStrategy(24);
    }

    /*function _preHardWork() internal override {
        IGaugeV2_CL gauge = IGaugeV2_CL(IFarmingStrategy(currentStrategy).stakingPool());
        IVoterV3 voter = IVoterV3(gauge.DISTRIBUTION());
        address minter = voter.minter();
        address[] memory gauges = new address[](1);
        gauges[0] = address(gauge);
        // uint rewardAmount = 1e18;
        // _deal(SonicConstantsLib.TOKEN_SWPX, minter, rewardAmount);
        vm.startPrank(minter);
        // IERC20(SonicConstantsLib.TOKEN_SWPX).approve(address(voter), type(uint).max);
        // voter.notifyRewardAmount(rewardAmount);
        voter.distribute(gauges);
        vm.stopPrank();
    }*/

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.ICHI_SWAPX_FARM,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }
}
