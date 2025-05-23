// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";

contract DeployMetaVault is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new MetaVault();
        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
