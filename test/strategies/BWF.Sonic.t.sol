// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";

contract BeetsWeightedFarmStrategyTest is SonicSetup, UniversalTest {
    function testBWF() public universalTest {
        _addStrategy(6);
        _addStrategy(17);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.BEETS_WEIGHTED_FARM,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }
}
