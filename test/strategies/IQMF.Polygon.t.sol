// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/PolygonSetup.sol";
import "../base/UniversalTest.sol";

contract IchiQuickSwapMerklFarmStrategyTest is PolygonSetup, UniversalTest {
    function testIQMF() public universalTest {
        _addStrategy(21);
        _addStrategy(22);
        _addStrategy(23);
        _addStrategy(40);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.ICHI_QUICKSWAP_MERKL_FARM,
                pool: address(0),
                farmId: farmId,
                underlying: address(0)
            })
        );
    }

    function _preHardWork() internal override {
        deal(PolygonLib.TOKEN_dQUICK, currentStrategy, 10e18);
        deal(PolygonLib.TOKEN_ICHI, currentStrategy, 10e18);
    }
}
