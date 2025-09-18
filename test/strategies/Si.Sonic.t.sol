// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {UniversalTest} from "../base/UniversalTest.sol";
import {SonicConstantsLib} from "chains/sonic/SonicConstantsLib.sol";
import {StrategyIdLib} from "src/strategies/libs/StrategyIdLib.sol";

contract SiloStrategySonicTest is SonicSetup, UniversalTest {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        //vm.rollFork(22435994); // Apr-26-2025 12:04:40 PM +UTC
        vm.rollFork(26826000); // May-14-2025 09:16:16 PM +UTC
    }

    function testSiloSonic() public universalTest {
        _addStrategy(SonicConstantsLib.SILO_VAULT_8_USDC);
        _addStrategy(SonicConstantsLib.SILO_VAULT_27_USDC);
        _addStrategy(SonicConstantsLib.SILO_VAULT_51_WS);
        _addStrategy(SonicConstantsLib.SILO_VAULT_31_WBTC);
    }

    function _addStrategy(address strategyInitAddress) internal {
        address[] memory initStrategyAddresses = new address[](1);
        initStrategyAddresses[0] = strategyInitAddress;

        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO,
                pool: address(0),
                farmId: type(uint).max,
                strategyInitAddresses: initStrategyAddresses,
                strategyInitNums: new uint[](0)
            })
        );
    }
}
