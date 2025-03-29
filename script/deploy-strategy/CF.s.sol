// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {CompoundFarmStrategy} from "../../src/strategies/CompoundFarmStrategy.sol";

contract DeployCF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new CompoundFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
