// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Frontend} from "../../src/periphery/Frontend.sol";

contract DeployFrontendAvalanche is Script {
    address public constant PLATFORM = 0x94ae77b4e2dbF7799f7c41da3F50aBeE12Fde70e;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new Frontend(PLATFORM);
        vm.stopBroadcast();
    }

    function testDeployPeriphery() external {}
}
