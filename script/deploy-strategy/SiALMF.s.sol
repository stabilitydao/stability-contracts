// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {SiloALMFStrategy} from "../../src/strategies/SiloALMFStrategy.sol";

contract DeploySiALMF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new SiloALMFStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
