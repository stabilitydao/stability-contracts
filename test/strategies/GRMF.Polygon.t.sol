// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/PolygonSetup.sol";
import "../base/UniversalTest.sol";

contract GammaRetroMerklFarmStrategyTest is PolygonSetup, UniversalTest {
    function testGRMF() public universalTest {
        _addStrategy(29);
        _addStrategy(30);
        _addStrategy(31);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.GAMMA_RETRO_MERKL_FARM,
                pool: address(0),
                farmId: farmId,
                underlying: address(0)
            })
        );
    }

    function _preHardWork() internal override {
        deal(PolygonLib.TOKEN_oRETRO, currentStrategy, 10e18);
    }
}
