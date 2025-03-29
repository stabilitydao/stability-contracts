// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {SteerQuickSwapMerklFarmStrategy} from "../../src/strategies/SteerQuickSwapMerklFarmStrategy.sol";

contract DeployStrategySQMF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new SteerQuickSwapMerklFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
