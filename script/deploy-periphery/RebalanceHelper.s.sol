// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {RebalanceHelper} from "../../src/periphery/RebalanceHelper.sol";

contract DeployRebalanceHelper is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new RebalanceHelper();
        vm.stopBroadcast();
    }

    function testDeployPeriphery() external {}
}
