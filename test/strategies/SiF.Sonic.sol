// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/SonicSetup.sol";
import "../base/UniversalTest.sol";

contract SiloFarmStrategyTest is SonicSetup, UniversalTest {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(5916871); // Jan-30-2025 04:32:17 PM +UTC
    }

    function testSiFSonic() public universalTest {
        _addStrategy(22);
        _addStrategy(32);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO_FARM,
                pool: address(0),
                farmId: farmId, // chains/SonicLib.sol
                strategyInitAddresses: new address[](0)
            })
        );
    }
}
