// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {MetaUsdAdapter} from "../../src/adapters/MetaUsdAdapter.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {UniversalTest} from "../base/UniversalTest.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";


contract SiloALMFStrategyTest is SonicSetup, UniversalTest {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(34471950); // Jun-17-2025 09:08:37 AM +UTC
        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;
    }

    function testSiALMFSonic() public universalTest {
        _addStrategy(52);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO_ALMF,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }

    //region --------------------------------------- Helper functions
    //endregion --------------------------------------- Helper functions
}
