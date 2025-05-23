// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {WrappedMetaVault} from "../../src/core/vaults/WrappedMetaVault.sol";

contract WrappedDeployMetaVault is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new WrappedMetaVault();
        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
