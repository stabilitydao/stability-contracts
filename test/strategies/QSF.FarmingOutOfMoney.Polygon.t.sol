// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/UniversalTest.sol";
import "../base/chains/PolygonSetup.sol";

contract QuickSwapV3StaticFarmStrategyFarmingOutOfMoneyTest is PolygonSetup, UniversalTest {
    address algebraEternalFarming = 0x8a26436e41d0b5fc4C6Ed36C1976fafBe173444E;

    function testStrategyUniversal() public universalTest {
        strategies.push(
            Strategy({id: StrategyIdLib.QUICKSWAPV3_STATIC_FARM, pool: address(0), farmId: 0, underlying: address(0)})
        );
    }

    function _preHardWork() internal virtual override {
        deal(PolygonLib.TOKEN_dQUICK, algebraEternalFarming, 0);
    }
}
