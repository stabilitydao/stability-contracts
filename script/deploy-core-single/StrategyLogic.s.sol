// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {StrategyLogic} from "../../src/core/StrategyLogic.sol";

contract DeployStrategyLogic is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new StrategyLogic();
        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
