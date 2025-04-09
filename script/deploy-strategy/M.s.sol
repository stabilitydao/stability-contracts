// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {MachStrategy} from "../../src/strategies/MachStrategy.sol";

contract DeployStrategyM is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new MachStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
