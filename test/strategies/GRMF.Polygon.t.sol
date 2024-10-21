// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/PolygonSetup.sol";
import "../base/UniversalTest.sol";
import "../../src/strategies/GammaRetroMerklFarmStrategy.sol";

contract GammaRetroMerklFarmStrategyTest is PolygonSetup, UniversalTest {
    constructor() {
        vm.rollFork(55000000); // Mar-23-2024 07:56:52 PM +UTC
    }

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

        // cover flash swap callback reverts
        vm.expectRevert(GammaRetroMerklFarmStrategy.NotFlashPool.selector);
        GammaRetroMerklFarmStrategy(currentStrategy).uniswapV3FlashCallback(0, 0, "");

        vm.expectRevert(GammaRetroMerklFarmStrategy.PairReentered.selector);
        vm.prank(PolygonLib.POOL_RETRO_USDCe_CASH_100);
        GammaRetroMerklFarmStrategy(currentStrategy).uniswapV3FlashCallback(0, 0, "");
    }
}
