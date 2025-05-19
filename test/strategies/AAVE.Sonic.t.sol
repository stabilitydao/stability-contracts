// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SonicSetup, SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";

contract AaveStrategyTestSonic is SonicSetup, UniversalTest {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(22116484); // Apr-25-2025 01:47:21 AM +UTC
        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;
    }

    function testAaveStrategy() public universalTest {
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_wS);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_USDC);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_scUSD);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_WETH);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_USDT);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_wOS);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_stS);
    }

    function _addStrategy(address aToken) internal {
        address[] memory initStrategyAddresses = new address[](1);
        initStrategyAddresses[0] = aToken;
        strategies.push(
            Strategy({
                id: StrategyIdLib.AAVE,
                pool: address(0),
                farmId: type(uint).max,
                strategyInitAddresses: initStrategyAddresses,
                strategyInitNums: new uint[](0)
            })
        );
    }
}
