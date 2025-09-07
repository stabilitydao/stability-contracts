// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";

contract SiloFarmStrategyTest is SonicSetup, UniversalTest {
    constructor() {
        vm.rollFork(32000000); // Jun-05-2025 09:41:47 AM +UTC
    }

    function testSiFSonic() public universalTest {
        _addStrategy(22);
        _addStrategy(23);
        _addStrategy(52);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO_FARM,
                pool: address(0),
                farmId: farmId, // chains/sonic/SonicLib.sol
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }
}
