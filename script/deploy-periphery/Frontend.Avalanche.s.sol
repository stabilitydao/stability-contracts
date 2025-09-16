// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Frontend} from "../../src/periphery/Frontend.sol";

contract DeployFrontendAvalanche is Script {
    address public constant PLATFORM = 0x72b931a12aaCDa6729b4f8f76454855CB5195941;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new Frontend(PLATFORM);
        vm.stopBroadcast();
    }

    function testDeployPeriphery() external {}
}
