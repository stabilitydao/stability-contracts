// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";

contract DeployCVault is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new CVault();
        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
