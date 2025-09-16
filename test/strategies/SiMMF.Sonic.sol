// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
import {SonicLib, SonicConstantsLib} from "../../chains/sonic/SonicLib.sol";

contract SiloManagedMerklFarmStrategyTest is SonicSetup, UniversalTest {
    uint private constant FORK_BLOCK = 47005295; // Sep-16-2025 05:50:01 AM +UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(FORK_BLOCK);
    }

    function testSiMMFSonic() public universalTest {
        _addStrategy(64);
    }

    function _preHardWork() internal override {
        // emulate Merkl-rewards
        deal(SonicConstantsLib.TOKEN_USDC, currentStrategy, 1e6);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO_MANAGED_MERKL_FARM,
                pool: address(0),
                farmId: farmId, // chains/sonic/SonicLib.sol
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }
}
