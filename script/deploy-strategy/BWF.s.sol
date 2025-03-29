// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {BeetsWeightedFarm} from "../../src/strategies/BeetsWeightedFarm.sol";

contract DeployBWF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new BeetsWeightedFarm();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
