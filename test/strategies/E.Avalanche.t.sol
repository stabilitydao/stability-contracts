// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// import {console} from "forge-std/Test.sol";
import {AvalancheConstantsLib} from "../../chains/avalanche/AvalancheConstantsLib.sol";
import {AvalancheSetup} from "../base/chains/AvalancheSetup.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";

contract EulerStrategyTestAvalanche is AvalancheSetup, UniversalTest {
    uint public constant FORK_BLOCK_C_CHAIN = 68407132; // Sep-8-2025 09:54:05 UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("AVALANCHE_RPC_URL"), FORK_BLOCK_C_CHAIN));
        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;
    }

    function testEulerStrategy() public universalTest {
        _addStrategy(AvalancheConstantsLib.EULER_VAULT_USDT_K3);
        _addStrategy(AvalancheConstantsLib.EULER_VAULT_USDC_RE7);
    }

    function _addStrategy(address eulerVault) internal {
        address[] memory initStrategyAddresses = new address[](1);
        initStrategyAddresses[0] = eulerVault;
        strategies.push(
            Strategy({
                id: StrategyIdLib.EULER,
                pool: address(0),
                farmId: type(uint).max,
                strategyInitAddresses: initStrategyAddresses,
                strategyInitNums: new uint[](0)
            })
        );
    }

    function _preDeposit() internal view override {
        assertEq(IStrategy(currentStrategy).strategyLogicId(), StrategyIdLib.EULER);
        // console.log(IStrategy(currentStrategy).description());
        // {(string memory name,) = IStrategy(currentStrategy).getSpecificName(); console.log(name);}
    }
}
