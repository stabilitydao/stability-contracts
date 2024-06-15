// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/BaseSetup.sol";
import "../base/UniversalTest.sol";

contract CompoundFarmStrategyTest is BaseSetup, UniversalTest {
    function testCFBase() public universalTest {
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
                farmId: farmId, // chains/BaseLib.sol
                underlying: address(0)
            })
        );
    }
}
