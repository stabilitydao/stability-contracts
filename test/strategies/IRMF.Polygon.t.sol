// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/PolygonSetup.sol";
import "../base/UniversalTest.sol";

contract IchiRetroMerklFarmStrategyTest is PolygonSetup, UniversalTest {
    function testIRMF() public universalTest {
        _addStrategy(24);
        _addStrategy(25);
        _addStrategy(26);
        _addStrategy(27);
        _addStrategy(28);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({id: StrategyIdLib.ICHI_RETRO_MERKL_FARM, pool: address(0), farmId: farmId, underlying: address(0)})
        );
    }

    function _preHardWork() internal override {
        deal(PolygonLib.TOKEN_oRETRO, currentStrategy, 10e18);
    }
}
