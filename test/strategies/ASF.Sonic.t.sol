// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import "../../chains/SonicLib.sol";
import "../base/UniversalTest.sol";

contract ALMShadowFarmStrategyTest is SonicSetup, UniversalTest {
    constructor() {}

    function testASF() public universalTest {
        _addStrategy(22); // wS_WETH 3000
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({id: StrategyIdLib.ALM_SHADOW_FARM, pool: address(0), farmId: farmId, underlying: address(0)})
        );
    }
}
