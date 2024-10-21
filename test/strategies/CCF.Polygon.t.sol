// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/PolygonSetup.sol";
import "../base/UniversalTest.sol";

contract CurveConvexFarmStrategyTest is PolygonSetup, UniversalTest {
    constructor() {
        vm.rollFork(55000000); // Mar-23-2024 07:56:52 PM +UTC
    }

    function testCCF() public universalTest {
        _addStrategy(34);
        _addStrategy(35);
        _addStrategy(36);
        _addStrategy(37);
        duration1 = 2 hours;
        duration2 = 1 hours;
        duration3 = 1 hours;
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({id: StrategyIdLib.CURVE_CONVEX_FARM, pool: address(0), farmId: farmId, underlying: address(0)})
        );
    }
}
