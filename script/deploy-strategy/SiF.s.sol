// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {SiloFarmStrategy} from "../../src/strategies/SiloFarmStrategy.sol";

contract DeploySiF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new SiloFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
