// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SonicSetup, SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
// import {console, Test} from "forge-std/Test.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";

contract EulerStrategyTestSonic is SonicSetup, UniversalTest {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        // vm.rollFork(22116484); // Apr-25-2025 01:47:21 AM +UTC
        vm.rollFork(28450562); // May-21-2025 09:02:18 AM +UTC
        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;

        //    console.log("erc7201:stability.EulerStrategy");
        //    console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.EulerStrategy")) - 1)) & ~bytes32(uint256(0xff)));
    }

    function testEulerStrategy() public universalTest {
        _addStrategy(SonicConstantsLib.EULER_VAULT_wS_Re7);
        _addStrategy(SonicConstantsLib.EULER_VAULT_scUSD_Re7);
        _addStrategy(SonicConstantsLib.EULER_VAULT_scUSD_MEV);
        _addStrategy(SonicConstantsLib.EULER_VAULT_scETH_MEV);
        _addStrategy(SonicConstantsLib.EULER_VAULT_WETH_MEV);
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
