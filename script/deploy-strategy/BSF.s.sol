// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {BeetsStableFarm} from "../../src/strategies/BeetsStableFarm.sol";

contract DeployBSF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new BeetsStableFarm();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
