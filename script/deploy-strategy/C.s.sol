// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {CompoundV2Strategy} from "../../src/strategies/CompoundV2Strategy.sol";

contract DeployC is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new CompoundV2Strategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
