// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";

contract ShadowFarmStrategyTest is SonicSetup, UniversalTest {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(22729698); // Apr-27-2025 09:21:40 PM +UTC
        depositedSharesCheckDelimiter = 100;
        makePoolVolume = false;
        makePoolVolumePriceImpactTolerance = 10_000;
    }

    function testShF() public universalTest {
        _addStrategy(42);
        // _addStrategy(43);
        // _addStrategy(44);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.SHADOW_FARM,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }
}
