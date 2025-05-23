// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";

contract EulerMerklFarmStrategyTestSonic is SonicSetup, UniversalTest {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(21094354); // Apr-19-2025 10:09:35 PM +UTC
        makePoolVolumePriceImpactTolerance = 9_000;
    }

    function testEMF() public universalTest {
        _addStrategy(42);
        _addStrategy(43);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.EULER_MERKL_FARM,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }

    function _preHardWork() internal override {
        // emulate rewards receiving (workaround difficulties with merkl claiming)
        deal(SonicConstantsLib.TOKEN_rEUL, currentStrategy, 10e18);
    }
}
