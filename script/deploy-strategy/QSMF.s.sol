// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {QuickSwapStaticMerklFarmStrategy} from "../../src/strategies/QuickSwapStaticMerklFarmStrategy.sol";

contract DeployStrategyQSMF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new QuickSwapStaticMerklFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
