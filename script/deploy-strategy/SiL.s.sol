// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {SiloLeverageStrategy} from "../../src/strategies/SiloLeverageStrategy.sol";

contract DeploySiL is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new SiloLeverageStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
