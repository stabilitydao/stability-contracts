// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {ALMShadowFarmStrategy} from "../../src/strategies/ALMShadowFarmStrategy.sol";

contract DeployASF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new ALMShadowFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
