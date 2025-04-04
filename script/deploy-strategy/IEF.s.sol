// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {IchiEqualizerFarmStrategy} from "../../src/strategies/IchiEqualizerFarmStrategy.sol";

contract DeployStrategyIEF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new IchiEqualizerFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
