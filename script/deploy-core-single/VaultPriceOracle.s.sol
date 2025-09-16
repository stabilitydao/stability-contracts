// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {VaultPriceOracle} from "../../src/core/VaultPriceOracle.sol";

contract DeployVaultPriceOracle is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new VaultPriceOracle();
        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
