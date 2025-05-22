// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/SonicSetup.sol";
import "../base/UniversalTest.sol";
import "../../src/integrations/silo/ISiloVault.sol";

contract SiloManagedFarmStrategyTest is SonicSetup, UniversalTest {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(28687311); // May-22-2025 07:13:50 AM +UTC
    }
    function testSiMFSonic() public universalTest {
        _addStrategy(43);
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
