// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/RealSetup.sol";
import "../base/UniversalTest.sol";

contract TridentPearlFarmStrategyTest is RealSetup, UniversalTest {
    receive() external payable {}

    function testTPF() public universalTest {
        _addStrategy(0);
        _addStrategy(1);
        //        _addStrategy(2);
        //        _addStrategy(3);
        //        _addStrategy(4);
        //        _addStrategy(6);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({id: StrategyIdLib.TRIDENT_PEARL_FARM, pool: address(0), farmId: farmId, underlying: address(0)})
        );
    }
}
