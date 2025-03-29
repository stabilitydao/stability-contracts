// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {DefiEdgeQuickSwapMerklFarmStrategy} from "../../src/strategies/DefiEdgeQuickSwapMerklFarmStrategy.sol";

contract DeployStrategyDQMF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new DefiEdgeQuickSwapMerklFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
