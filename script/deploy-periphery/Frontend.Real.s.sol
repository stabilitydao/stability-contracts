// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {Frontend} from "../../src/periphery/Frontend.sol";

contract DeployFrontendReal is Script {
    address public constant PLATFORM = 0xB7838d447deece2a9A5794De0f342B47d0c1B9DC;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new Frontend(PLATFORM);
        vm.stopBroadcast();
    }

    function testDeployPeriphery() external {}
}
