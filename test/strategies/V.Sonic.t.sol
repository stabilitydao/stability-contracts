// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SonicSetup, SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";

contract VicunaStrategyTestSonic is SonicSetup, UniversalTest {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(22116484); // Apr-25-2025 01:47:21 AM +UTC
        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;
    }

    function testVicunaStrategy() public universalTest {
        _addStrategy(SonicConstantsLib.VICUNA_SONIC_wS);
        _addStrategy(SonicConstantsLib.VICUNA_SONIC_USDC);
        _addStrategy(SonicConstantsLib.VICUNA_SONIC_scUSD);
        _addStrategy(SonicConstantsLib.VICUNA_SONIC_WETH);
        _addStrategy(SonicConstantsLib.VICUNA_SONIC_USDT);
        _addStrategy(SonicConstantsLib.VICUNA_SONIC_wOS);
        _addStrategy(SonicConstantsLib.VICUNA_SONIC_stS);
    }

    function _addStrategy(address aToken) internal {
        address[] memory initStrategyAddresses = new address[](1);
        initStrategyAddresses[0] = aToken;
        strategies.push(
            Strategy({
                id: StrategyIdLib.VICUNA,
                pool: address(0),
                farmId: type(uint).max,
                strategyInitAddresses: initStrategyAddresses,
                strategyInitNums: new uint[](0)
            })
        );
    }
}
