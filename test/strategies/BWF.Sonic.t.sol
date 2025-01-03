// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import "../base/UniversalTest.sol";

contract BeetsWeightedFarmStrategyTest is SonicSetup, UniversalTest {
    function testBWF() public universalTest {
        _addStrategy(6);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({id: StrategyIdLib.BEETS_WEIGHTED_FARM, pool: address(0), farmId: farmId, underlying: address(0)})
        );
    }
}
