// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {Platform} from "../../src/core/Platform.sol";
import {Factory} from "../../src/core/Factory.sol";

abstract contract ChainSetup is Test {
    Platform public platform;
    Factory public factory;

    function testChainSetupStub() public {}

    function _init() internal virtual;

    function _deal(address token, address to, uint amount) internal virtual;
}
