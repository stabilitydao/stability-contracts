// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/PolygonSetup.sol";
import "../base/UniversalTest.sol";

contract CompoundFarmStrategyTest is PolygonSetup, UniversalTest {
    function testCompoundStrategy() public universalTest {
        strategies.push(
            Strategy({
                id: StrategyIdLib.COMPOUND_FARM,
                pool: address(0),
                farmId: 17, // chains/PolygonLib.sol
                underlying: address(0)
            })
        );
    }
}
