// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Factory} from "../../src/core/Factory.sol";
import {Script} from "forge-std/Script.sol";

contract DeployFactory is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new Factory();
        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
