// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/PolygonSetup.sol";
import "../base/UniversalTest.sol";

contract QuickSwapV3StaticFarmStrategyTest is PolygonSetup, UniversalTest {
    function testStrategyUniversal() public universalTest {
        strategies.push(
            Strategy({
                id: StrategyIdLib.QUICKSWAPV3_STATIC_FARM,
                pool: address(0),
                farmId: 0, // chains/PolygonLib.sol
                underlying: address(0)
            })
        );
        strategies.push(
            Strategy({
                id: StrategyIdLib.QUICKSWAPV3_STATIC_FARM,
                pool: address(0),
                farmId: 16, // chains/PolygonLib.sol
                underlying: address(0)
            })
        );
    }
}
