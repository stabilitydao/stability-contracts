// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AvalancheSetup} from "../base/chains/AvalancheSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
import {AvalancheLib, AvalancheConstantsLib} from "../../chains/avalanche/AvalancheLib.sol";

contract SiloMerklFarmStrategyAvalancheTest is AvalancheSetup, UniversalTest {
    uint public constant FORK_BLOCK_C_CHAIN = 68876829; // Sep-17-2025 12:09:57 UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("AVALANCHE_RPC_URL"), FORK_BLOCK_C_CHAIN));
    }

    function testSiFAvalanche() public universalTest {
        _addStrategy(8);
        _addStrategy(9); // todo compound apr??
        _addStrategy(10);
        _addStrategy(11); // todo compound apr??
    }

    //region -------------------------------- Universal test overrides
    function _preHardWork() internal override {
        // emulate Merkl-rewards
        deal(AvalancheConstantsLib.TOKEN_USDC, currentStrategy, 1e6);
    }
    //endregion -------------------------------- Universal test overrides

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO_MERKL_FARM,
                pool: address(0),
                farmId: farmId, // chains/avalanche/AvalancheLib.sol
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }
}
