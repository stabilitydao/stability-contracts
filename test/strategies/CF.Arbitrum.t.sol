// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/ArbitrumSetup.sol";
import "../base/UniversalTest.sol";

contract CompoundFarmStrategyTest is ArbitrumSetup, UniversalTest {
    function testCFArbitrum() public universalTest {
        buildingPayPerVaultTokenAmount = 1e6 * 100000;
        _addStrategy(0);
        _addStrategy(1);
        _addStrategy(2);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.COMPOUND_FARM,
                pool: address(0),
                farmId: farmId, // chains/ArbitrumLib.sol
                underlying: address(0)
            })
        );
    }
}
