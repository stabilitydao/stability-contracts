// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {RevenueRouter} from "../../src/tokenomics/RevenueRouter.sol";

contract DeployRevenueRouter is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new RevenueRouter();
        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
