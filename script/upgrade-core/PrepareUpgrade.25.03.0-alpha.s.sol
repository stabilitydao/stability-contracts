// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {Swapper} from "../../src/core/Swapper.sol";

contract PrepareUpgrade8 is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        // Swapper 1.1.0: long routes
        new Swapper();
        vm.stopBroadcast();
    }

    function testPrepareUpgrade() external {}
}
