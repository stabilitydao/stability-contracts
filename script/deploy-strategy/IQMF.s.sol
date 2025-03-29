// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {IchiQuickSwapMerklFarmStrategy} from "../../src/strategies/IchiQuickSwapMerklFarmStrategy.sol";

contract DeployStrategyIQMF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new IchiQuickSwapMerklFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
