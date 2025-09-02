// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MetaVaultFactory} from "../../src/core/MetaVaultFactory.sol";
import {Script} from "forge-std/Script.sol";

contract DeployMetaVaultFactory is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new MetaVaultFactory();
        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
