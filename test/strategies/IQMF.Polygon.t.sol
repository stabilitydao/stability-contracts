// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/PolygonSetup.sol";
import "../base/UniversalTest.sol";

contract IchiQuickSwapMerklFarmStrategyTest is PolygonSetup, UniversalTest {
    function testStrategyUniversal() public universalTest {
        strategies.push(
            Strategy({
                id: StrategyIdLib.ICHI_QUICKSWAP_MERKL_FARM,
                pool: address(0),
                farmId: 0, // chains/PolygonLib.sol
                underlying: address(0)
            })
        );
    }
}
