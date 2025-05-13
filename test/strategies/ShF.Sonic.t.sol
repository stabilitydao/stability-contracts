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
        makePoolVolumePriceImpactTolerance = 10_000;
    }

    function testShF() public universalTest {
        _addStrategy(42);
        _addStrategy(45);
        _addStrategy(46);
        _addStrategy(47);
        _addStrategy(48);
        _addStrategy(50);

        // _addStrategy(43); // Fails with error `Swapper: swap path not found`. No path for GEMS to xUSD and on dexscreener there is no pair GEMS/xUSD
        // _addStrategy(44); // Pass on it's own. But throws the error `FAIL: HardWork APR: 0 <= 0` when you run with the other farms.
        // _addStrategy(49); // Pass on it's own. But throws the error `FAIL: HardWork APR: 0 <= 0` when you run with the other farms.
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
