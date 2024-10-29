// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/RealSetup.sol";
import "../base/UniversalTest.sol";

contract TridentPearlFarmStrategyTest is RealSetup, UniversalTest {
    receive() external payable {}

    function testTPF() public universalTest {
        for (uint i; i < 5; ++i) {
            _addStrategy(i);
        }
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({id: StrategyIdLib.TRIDENT_PEARL_FARM, pool: address(0), farmId: farmId, underlying: address(0)})
        );
    }
}
