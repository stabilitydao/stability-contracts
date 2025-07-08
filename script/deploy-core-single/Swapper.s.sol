// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Swapper} from "../../src/core/Swapper.sol";
import {Script} from "forge-std/Script.sol";

contract DeploySwapper is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new Swapper();
        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
