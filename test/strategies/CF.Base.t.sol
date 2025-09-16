// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BaseSetup} from "../base/chains/BaseSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";

contract CompoundFarmStrategyTest is BaseSetup, UniversalTest {
    function testCFBase() public universalTest {
        _addStrategy(0);
        _addStrategy(1);
        _addStrategy(2);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.COMPOUND_FARM,
                pool: address(0),
                farmId: farmId, // chains/BaseLib.sol
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }
}
