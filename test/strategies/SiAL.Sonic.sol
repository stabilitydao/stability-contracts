// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {UniversalTest} from "../base/UniversalTest.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";

contract SiloAdvancedLeverageStrategyTest is SonicSetup, UniversalTest {
    constructor() {
        //vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        //vm.rollFork(11356000); // Mar-03-2025 08:19:49 AM +UTC
        //vm.rollFork(13119000); // Mar-11-2025 08:29:09 PM +UTC
        vm.rollFork(18553912); // Apr-01-2025 03:26:51 PM +UTC
        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;
    }

    function testSiALSonic() public universalTest {
        // Initialize first strategy
        address[] memory initStrategyAddresses1 = new address[](4);
        initStrategyAddresses1[0] = SonicConstantsLib.SILO_VAULT_46_PT_aUSDC_14AUG;
        initStrategyAddresses1[1] = SonicConstantsLib.SILO_VAULT_46_scUSD;
        initStrategyAddresses1[2] = SonicConstantsLib.BEETS_VAULT;
        initStrategyAddresses1[3] = SonicConstantsLib.SILO_LENS;
        uint[] memory strategyInitNums1 = new uint[](1);
        strategyInitNums1[0] = 60_00;
        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO_ADVANCED_LEVERAGE,
                pool: address(0),
                farmId: type(uint).max,
                strategyInitAddresses: initStrategyAddresses1,
                strategyInitNums: strategyInitNums1
            })
        );

        // Initialize second strategy
        address[] memory initStrategyAddresses2 = new address[](4);
        initStrategyAddresses2[0] = SonicConstantsLib.SILO_VAULT_40_PT_stS_29MAY;
        initStrategyAddresses2[1] = SonicConstantsLib.SILO_VAULT_40_wS;
        initStrategyAddresses2[2] = SonicConstantsLib.BEETS_VAULT;
        initStrategyAddresses2[3] = SonicConstantsLib.SILO_LENS;
        uint[] memory strategyInitNums2 = new uint[](1);
        strategyInitNums2[0] = 65_00;
        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO_ADVANCED_LEVERAGE,
                pool: address(0),
                farmId: type(uint).max,
                strategyInitAddresses: initStrategyAddresses2,
                strategyInitNums: strategyInitNums2
            })
        );
    }

    function _addStrategy(
        address strategyInitAddress0,
        address strategyInitAddress1,
        uint targetLeveragePercent
    ) internal {
        address[] memory initStrategyAddresses = new address[](4);
        initStrategyAddresses[0] = strategyInitAddress0;
        initStrategyAddresses[1] = strategyInitAddress1;
        initStrategyAddresses[2] = SonicConstantsLib.BEETS_VAULT;
        initStrategyAddresses[3] = SonicConstantsLib.SILO_LENS;
        uint[] memory strategyInitNums = new uint[](1);
        strategyInitNums[0] = targetLeveragePercent;
        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO_ADVANCED_LEVERAGE,
                pool: address(0),
                farmId: type(uint).max,
                strategyInitAddresses: initStrategyAddresses,
                strategyInitNums: strategyInitNums
            })
        );
    }
}
