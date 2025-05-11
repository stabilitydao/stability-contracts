// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {MockSetup} from "../base/MockSetup.sol";

contract AgentOSTest is Test, MockSetup {
    function setUp() public pure {
        // console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.AgentOS")) - 1)) & ~bytes32(uint256(0xff)));
    }
}
