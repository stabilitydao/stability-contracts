// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/PolygonSetup.sol";
import "../base/UniversalTest.sol";

contract QuickswapStaticMerklFarmStrategyTest is PolygonSetup, UniversalTest {
    function testQSMF() public universalTest {
        // starategy push
        strategies.push(
            Strategy({
                id: StrategyIdLib.QUICKSWAP_STATIC_MERKL_FARM,
                pool: address(0),
                farmId: 0, // chains/PolygonLib.sol
                underlying: address(0)
            })
        );
        strategies.push(
            Strategy({
                id: StrategyIdLib.QUICKSWAP_STATIC_MERKL_FARM,
                pool: address(0),
                farmId: 16, // chains/PolygonLib.sol
                underlying: address(0)
            })
        );
    }

    function _preHardWork() internal override {
        deal(PolygonLib.TOKEN_dQUICK, currentStrategy, 10e18);
    }
}
