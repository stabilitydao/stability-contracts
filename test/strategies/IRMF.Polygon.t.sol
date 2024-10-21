// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/UniversalTest.sol";
import "../base/chains/PolygonSetup.sol";
import "../../src/strategies/IchiRetroMerklFarmStrategy.sol";

contract IchiRetroMerklFarmStrategyTest is PolygonSetup, UniversalTest {
    constructor() {
        vm.rollFork(55000000); // Mar-23-2024 07:56:52 PM +UTC
    }

    function testIchiRetroMerklFarmStrategy() public universalTest {
        _addStrategy(24);
        _addStrategy(25);
        _addStrategy(26);
        _addStrategy(27);
        _addStrategy(28);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({id: StrategyIdLib.ICHI_RETRO_MERKL_FARM, pool: address(0), farmId: farmId, underlying: address(0)})
        );
    }

    function _preHardWork() internal override {
        deal(PolygonLib.TOKEN_oRETRO, currentStrategy, 10e18);

        // cover flash swap callback reverts
        vm.expectRevert(IchiRetroMerklFarmStrategy.NotFlashPool.selector);
        IchiRetroMerklFarmStrategy(currentStrategy).uniswapV3FlashCallback(0, 0, "");

        vm.expectRevert(IchiRetroMerklFarmStrategy.PairReentered.selector);
        vm.prank(PolygonLib.POOL_RETRO_USDCe_CASH_100);
        IchiRetroMerklFarmStrategy(currentStrategy).uniswapV3FlashCallback(0, 0, "");
    }
}
