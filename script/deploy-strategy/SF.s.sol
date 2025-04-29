// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {SwapXFarmStrategy} from "../../src/strategies/SwapXFarmStrategy.sol";

contract DeploySF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new SwapXFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
