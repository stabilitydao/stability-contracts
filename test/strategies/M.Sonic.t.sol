// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SonicSetup, SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";

contract MachStrategyTestSonic is SonicSetup, UniversalTest {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(18692101); // Apr-07-2025 09:22:44 AM +UTC
        makePoolVolumePriceImpactTolerance = 9_000;
    }

    function testMachStrategy() public universalTest {
        // _addStrategy(31);
        // _addStrategy(32);
        // _addStrategy(33);
        _addStrategy(SonicConstantsLib.MACH_USDCe);
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
