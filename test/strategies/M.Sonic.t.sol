// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SonicSetup, SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";

contract MachStrategyTestSonic is SonicSetup, UniversalTest {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(18692101); // Apr-07-2025 09:22:44 AM +UTC
        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;
    }

    function testMachStrategy() public universalTest {
        _addStrategy(SonicConstantsLib.MACH_USDCe);
        _addStrategy(SonicConstantsLib.MACH_WETH);
        _addStrategy(SonicConstantsLib.MACH_stS);
        _addStrategy(SonicConstantsLib.MACH_scUSD);
        _addStrategy(SonicConstantsLib.MACH_scETH);
        _addStrategy(SonicConstantsLib.MACH_wOS);
        // _addStrategy(SonicConstantsLib.MACH_scBTC);
    }

    function _addStrategy(address cToken) internal {
        address[] memory initStrategyAddresses = new address[](1);
        initStrategyAddresses[0] = cToken;
        strategies.push(
            Strategy({
                id: StrategyIdLib.MACH,
                pool: address(0),
                farmId: type(uint).max,
                strategyInitAddresses: initStrategyAddresses,
                strategyInitNums: new uint[](0)
            })
        );
    }
}
