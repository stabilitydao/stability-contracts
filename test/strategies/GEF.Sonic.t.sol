// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";

contract GammaEqualizerFarmStrategyTestSonic is SonicSetup, UniversalTest {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(16088032); // Mar-26-2025 12:46:06 PM +UTC
        makePoolVolumePriceImpactTolerance = 9_000;
    }

    function testGEF() public universalTest {
        _addStrategy(31);
        _addStrategy(32);
        _addStrategy(33);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.GAMMA_EQUALIZER_FARM,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }
}
