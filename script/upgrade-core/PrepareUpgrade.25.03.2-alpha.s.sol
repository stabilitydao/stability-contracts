// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {Platform} from "../../src/core/Platform.sol";

contract PrepareUpgrade10 is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // Platform 1.2.0: revenueRouter
        new Platform();
        vm.stopBroadcast();
    }

    function testPrepareUpgrade() external {}
}
