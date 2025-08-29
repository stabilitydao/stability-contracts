// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {Factory} from "../../src/core/Factory.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {RVault} from "../../src/core/vaults/RVault.sol";
import {RMVault} from "../../src/core/vaults/RMVault.sol";
import {YearnStrategy} from "../../src/strategies/YearnStrategy.sol";

contract PrepareUpgrade5 is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Factory 1.1.0: getDeploymentKey fix for not farming strategies, strategyAvailableInitParams
        new Factory();

        // CVault 1.3.0: VaultBase 1.3.0
        new CVault();

        // RVault 1.3.0: VaultBase 1.3.0
        new RVault();

        // RMVault 1.3.0: VaultBase 1.3.0
        new RMVault();

        // new strategy implementation
        new YearnStrategy();

        vm.stopBroadcast();
    }

    function testPrepareUpgrade() external {}
}
