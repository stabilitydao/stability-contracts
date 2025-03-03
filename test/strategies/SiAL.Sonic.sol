// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {SonicLib} from "../../chains/SonicLib.sol";
import {UniversalTest} from "../base/UniversalTest.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";

contract SiloAdvancedLeverageStrategyTest is SonicSetup, UniversalTest {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(11356000); // Mar-03-2025 08:19:49 AM +UTC
        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;
    }

    function testSiALSonic() public universalTest {
        _addStrategy(SonicLib.SILO_VAULT_23_wstkscUSD, SonicLib.SILO_VAULT_23_USDC, 80_00);
        // not work because Swapper need support longer route
        //_addStrategy(SonicLib.SILO_VAULT_26_wstkscETH, SonicLib.SILO_VAULT_26_wETH, 80_00);
        //_addStrategy(SonicLib.SILO_VAULT_22_wOS, SonicLib.SILO_VAULT_22_wS, 87_00);
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
