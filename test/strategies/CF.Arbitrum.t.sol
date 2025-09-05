// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ArbitrumSetup} from "../base/chains/ArbitrumSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";

contract CompoundFarmStrategyTest is ArbitrumSetup, UniversalTest {
    function testCFArbitrum() public universalTest {
        _addStrategy(0);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.COMPOUND_FARM,
                pool: address(0),
                farmId: farmId, // chains/ArbitrumLib.sol
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }
}
