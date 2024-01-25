// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/PolygonSetup.sol";
import "../base/UniversalTest.sol";

contract IchiQuickSwapMerklFarmStrategyTest is PolygonSetup, UniversalTest {
    function testIQMF() public universalTest {
        strategies.push(
            Strategy({
                id: StrategyIdLib.ICHI_QUICKSWAP_MERKL_FARM,
                pool: address(0),
                farmId: 22, // chains/PolygonLib.sol
                underlying: address(0)
            })
        );
    }

    function _preHardWork() internal override {
        deal(PolygonLib.TOKEN_dQUICK, currentStrategy, 10e18);
    }
}
