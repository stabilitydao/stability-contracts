// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/SonicSetup.sol";
import "../base/UniversalTest.sol";

contract SiloStrategyTest is SonicSetup, UniversalTest {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(6548098); // Feb-04-2025 03:31:56 PM +UTC
    }

    function testSiFSonic() public universalTest {
        _addStrategy(SonicLib.SILO_VAULT_USDC_20);
    }

    function _addStrategy(address siloVault) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO,
                pool: address(0),   
                farmId: type(uint).max,
                underlying: siloVault
            })
        );
    }
}
