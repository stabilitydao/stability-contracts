// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {SiloStrategy} from "../../src/strategies/SiloStrategy.sol";

contract DeploySi is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new SiloStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
