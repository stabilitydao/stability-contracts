// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AvalancheSetup} from "../base/chains/AvalancheSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
import {AvalancheConstantsLib} from "../../chains/avalanche/AvalancheLib.sol";

contract SiloManagedMerklFarmStrategyAvalancheTest is AvalancheSetup, UniversalTest {
    // uint public constant FORK_BLOCK_C_CHAIN = 68407132; // Sep-8-2025 09:54:05 UTC
    uint public constant FORK_BLOCK_C_CHAIN = 68876829; // Sep-17-2025 12:09:57 UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("AVALANCHE_RPC_URL"), FORK_BLOCK_C_CHAIN));
        // console.log("factory", IPlatform(AvalancheConstantsLib.PLATFORM).factory());
    }

    function testSiMMFAvalanche() public universalTest {
        _addStrategy(4);
        _addStrategy(5);
        _addStrategy(6);
        _addStrategy(7);
    }

    function _preHardWork() internal override {
        // emulate Merkl-rewards
        deal(AvalancheConstantsLib.TOKEN_WAVAX, currentStrategy, 1e18);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO_MANAGED_MERKL_FARM,
                pool: address(0),
                farmId: farmId, // chains/Avalanche/AvalancheLib.sol
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }
}
