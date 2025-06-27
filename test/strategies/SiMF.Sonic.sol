// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/SonicSetup.sol";
import "../base/UniversalTest.sol";
import "../../src/integrations/silo/ISiloVault.sol";

contract SiloManagedFarmStrategyTest is SonicSetup, UniversalTest {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        // vm.rollFork(28738366); // May-22-2025 11:52:44 AM +UTC
        // vm.rollFork(28902958); // May-23-2025 03:13:18 AM +UTC
        vm.rollFork(35662058); // Jun-24-2025 09:03:06 AM +UTC
    }

    function testSiMFSonic() public universalTest {
        _addStrategy(42);
        _addStrategy(43);
        _addStrategy(44);
        _addStrategy(45);
        _addStrategy(46);
        _addStrategy(47);
        _addStrategy(48);
        _addStrategy(49);
        _addStrategy(50);
        _addStrategy(51);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO_MANAGED_FARM,
                pool: address(0),
                farmId: farmId, // chains/sonic/SonicLib.sol
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }
}
