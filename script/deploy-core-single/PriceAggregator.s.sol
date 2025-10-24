// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {PriceAggregator} from "../../src/core/PriceAggregator.sol";

contract DeployPriceAggregator is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new PriceAggregator();
        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
