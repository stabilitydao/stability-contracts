// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {IQMFLib} from "../../src/strategies/libs/IQMFLib.sol";
import {IRMFLib} from "../../src/strategies/libs/IRMFLib.sol";

contract LibsTest is Test {
    function testLibs() public {
        IQMFLib.getQuoteAtTick(887272 - 1, 1e10, address(1), address(2));
        IQMFLib.getQuoteAtTick(-887272 + 1, 1e10, address(1), address(2));

        vm.expectRevert(bytes("T"));
        IQMFLib.getQuoteAtTick(-8380606, 1e10, address(1), address(2));

        vm.expectRevert(bytes("T"));
        IQMFLib.getQuoteAtTick(-8380606, 1e10, address(3), address(2));

        IQMFLib.getQuoteAtTick(443637, 1e10, address(1), address(2));
        IRMFLib.getQuoteAtTick(443637, 1e10, address(1), address(2));
    }
}
