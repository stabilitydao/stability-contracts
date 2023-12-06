// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../base/chains/PolygonSetup.sol";
import "../base/UniversalTest.sol";
import "../../src/integrations/algebra/IAlgebraEternalFarming.sol";
import "../../src/interfaces/IFactory.sol";
import "../../src/interfaces/IPlatform.sol";
import {IncentiveKey} from "../../src/integrations/algebra/IncentiveKey.sol";

contract QuickSwapV3StaticFarmStrategyBonusReward is PolygonSetup, UniversalTest {
    function testStrategyUniversalP() public universalTest {
        strategies.push(
            Strategy({id: StrategyIdLib.QUICKSWAPV3_STATIC_FARM, pool: address(0), farmId: 0, underlying: address(0)})
        );
    }
}
