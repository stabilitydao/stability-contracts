// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import "../../src/core/Platform.sol";
import "../../src/core/Factory.sol";

abstract contract ChainSetup is Test {
    Platform public platform;
    Factory public factory;

    function testChainSetupStub() public {}

    function _init() internal virtual;

    function _deal(address token, address to, uint amount) internal virtual;
}
