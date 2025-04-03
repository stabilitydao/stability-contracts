// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {SonicLib} from "../../chains/SonicLib.sol";
import {UniversalTest} from "../base/UniversalTest.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";

contract SiloAdvancedLeverageStrategyTest is SonicSetup, UniversalTest {
    constructor() {
        //vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        //vm.rollFork(11356000); // Mar-03-2025 08:19:49 AM +UTC
        //vm.rollFork(13119000); // Mar-11-2025 08:29:09 PM +UTC
        vm.rollFork(17487000); // Apr-01-2025 03:26:51 PM +UTC
        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;
    }

    function testSiALSonic() public universalTest {
        //_addStrategy(SonicLib.SILO_VAULT_22_wOS, SonicLib.SILO_VAULT_22_wS, 86_90);
        //_addStrategy(SonicLib.SILO_VAULT_23_wstkscUSD, SonicLib.SILO_VAULT_23_USDC, 88_00);
        //_addStrategy(SonicLib.SILO_VAULT_26_wstkscETH, SonicLib.SILO_VAULT_26_wETH, 90_00);
        //_addStrategy(SonicLib.SILO_VAULT_25_wanS, SonicLib.SILO_VAULT_25_wS, 90_00);
        _addStrategy(SonicLib.SILO_VAULT_46_PT_aUSDC_14AUG, SonicLib.SILO_VAULT_46_scUSD, 60_00);
        _addStrategy(SonicLib.SILO_VAULT_40_PT_stS_29MAY, SonicLib.SILO_VAULT_40_wS, 65_00);
        //_addStrategy(SonicLib.SILO_VAULT_37_PT_wstkscUSD_29MAY, SonicLib.SILO_VAULT_37_frxUSD, 65_00);
    }

    function _addStrategy(
        address strategyInitAddress0,
        address strategyInitAddress1,
        uint targetLeveragePercent
    ) internal {
        address[] memory initStrategyAddresses = new address[](4);
        initStrategyAddresses[0] = strategyInitAddress0;
        initStrategyAddresses[1] = strategyInitAddress1;
        initStrategyAddresses[2] = SonicLib.BEETS_VAULT;
        initStrategyAddresses[3] = SonicLib.SILO_LENS;
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
