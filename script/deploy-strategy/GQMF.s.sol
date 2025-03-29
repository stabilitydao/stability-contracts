// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {GammaQuickSwapMerklFarmStrategy} from "../../src/strategies/GammaQuickSwapMerklFarmStrategy.sol";

contract DeployStrategyGQMF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new GammaQuickSwapMerklFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
