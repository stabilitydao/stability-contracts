// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {SonicLib} from "../../chains/SonicLib.sol";
import {UniversalTest} from "../base/UniversalTest.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";

contract SiloLeverageStrategyTest is SonicSetup, UniversalTest {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(7000000); // Feb-08-2025 08:32:32 AM +UTC
        //vm.rollFork(7283000); // Feb-10-2025 03:47:25 PM +UTC
        allowZeroApr = true;
        duration1 = 0.3 hours;
        duration2 = 0.1 hours;
        duration3 = 0.3 hours;
    }

    function testSiLSonic() public universalTest {
        _addStrategy(SonicLib.SILO_VAULT_3_stS, SonicLib.SILO_VAULT_3_wS);
        _addStrategy(SonicLib.SILO_VAULT_3_wS, SonicLib.SILO_VAULT_3_stS);
    }

    function _addStrategy(address strategyInitAddress0, address strategyInitAddress1) internal {
        address[] memory initStrategyAddresses = new address[](4);
        initStrategyAddresses[0] = strategyInitAddress0;
        initStrategyAddresses[1] = strategyInitAddress1;
        initStrategyAddresses[2] = SonicLib.BEETS_VAULT;
        initStrategyAddresses[3] = SonicLib.SILO_LENS;
        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO_LEVERAGE,
                pool: address(0),
                farmId: type(uint).max,
                strategyInitAddresses: initStrategyAddresses
            })
        );
    }
}
