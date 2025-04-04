// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {UniversalTest} from "../base/UniversalTest.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";

contract SiloLeverageStrategyTest is SonicSetup, UniversalTest {
    constructor() {
        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;
    }

    function testSiLSonic() public universalTest {
        _addStrategy(SonicConstantsLib.SILO_VAULT_3_stS, SonicConstantsLib.SILO_VAULT_3_wS);
        //_addStrategy(SonicConstantsLib.SILO_VAULT_3_wS, SonicConstantsLib.SILO_VAULT_3_stS);
    }

    function _addStrategy(address strategyInitAddress0, address strategyInitAddress1) internal {
        address[] memory initStrategyAddresses = new address[](4);
        initStrategyAddresses[0] = strategyInitAddress0;
        initStrategyAddresses[1] = strategyInitAddress1;
        initStrategyAddresses[2] = SonicConstantsLib.BEETS_VAULT;
        initStrategyAddresses[3] = SonicConstantsLib.SILO_LENS;
        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO_LEVERAGE,
                pool: address(0),
                farmId: type(uint).max,
                strategyInitAddresses: initStrategyAddresses,
                strategyInitNums: new uint[](0)
            })
        );
    }
}
