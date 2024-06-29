// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/ArbitrumSetup.sol";
import "../base/UniversalTest.sol";

contract CompoundFarmStrategyTest is ArbitrumSetup, UniversalTest {
    function testCFArbitrum() public universalTest {
        _addStrategy(0);
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
