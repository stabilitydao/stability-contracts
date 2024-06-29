// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/ArbitrumSetup.sol";
import "../base/UniversalTest.sol";

contract GammaUniswapV3MerklFarmStrategyTest is ArbitrumSetup, UniversalTest {
    function testGUMFArbitrum() public universalTest {
        _addStrategy(1);
        _addStrategy(2);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.GAMMA_UNISWAPV3_MERKL_FARM,
                pool: address(0),
                farmId: farmId,
                underlying: address(0)
            })
        );
    }

    function _preHardWork(uint farmId) internal override {
        IFactory.Farm memory f = factory.farm(farmId);
        deal(f.rewardAssets[0], currentStrategy, 1e18);
    }
}
