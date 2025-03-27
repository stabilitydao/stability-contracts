// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {GammaEqualizerFarmStrategy} from "../../src/strategies/GammaEqualizerFarmStrategy.sol";

contract DeployStrategyGEF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new GammaEqualizerFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
