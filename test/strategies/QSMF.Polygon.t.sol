// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/PolygonSetup.sol";
import "../base/UniversalTest.sol";

contract QuickswapStaticMerklFarmStrategyTest is PolygonSetup, UniversalTest {
    function testQSMF() public universalTest {
        _addStrategy(0);
        _addStrategy(16);
        _addStrategy(38);
        _addStrategy(39);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.QUICKSWAP_STATIC_MERKL_FARM,
                pool: address(0),
                farmId: farmId,
                underlying: address(0)
            })
        );
    }

    function _preHardWork() internal override {
        deal(PolygonLib.TOKEN_QUICK, currentStrategy, 10e18);
    }
}
