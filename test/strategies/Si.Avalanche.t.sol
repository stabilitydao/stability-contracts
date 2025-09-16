// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AvalancheSetup} from "../base/chains/AvalancheSetup.sol";
import {UniversalTest} from "../base/UniversalTest.sol";
import {AvalancheConstantsLib} from "chains/avalanche/AvalancheConstantsLib.sol";
import {StrategyIdLib} from "src/strategies/libs/StrategyIdLib.sol";

contract SiloStrategyAvalancheTest is AvalancheSetup, UniversalTest {
    uint public constant FORK_BLOCK_C_CHAIN = 68407132; // Sep-8-2025 09:54:05 UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("AVALANCHE_RPC_URL"), FORK_BLOCK_C_CHAIN));
    }

    function testSiloAvalanche() public universalTest {
        _addStrategy(AvalancheConstantsLib.SILO_VAULT_USDC_125);
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
