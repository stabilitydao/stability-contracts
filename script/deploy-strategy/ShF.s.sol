// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {ShadowFarmStrategy} from "../../src/strategies/ShadowFarmStrategy.sol";

contract DeployShF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new ShadowFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
