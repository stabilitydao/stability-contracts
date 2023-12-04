// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./MockStrategy.sol";

contract MockStrategyUpgrade is MockStrategy {
    function newFunc() external pure returns (uint) {
        return 1;
    }

    // add this to be excluded from coverage report
    function test() public {}
}
