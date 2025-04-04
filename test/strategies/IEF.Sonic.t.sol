// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";

contract IchiEqualizerFarmStrategyTestSonic is SonicSetup, UniversalTest {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(17034013); // Mar-30-2025 03:16:13 PM +UTC
        makePoolVolumePriceImpactTolerance = 9_000;
    }

    function testIEF() public universalTest {
        _addStrategy(34);
        _addStrategy(35);
        _addStrategy(36);
        _addStrategy(37);
        _addStrategy(38);
        _addStrategy(39);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.ICHI_EQUALIZER_FARM,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }
}
