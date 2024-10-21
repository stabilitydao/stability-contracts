// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/core/Factory.sol";
import "../../src/core/vaults/CVault.sol";
import "../../src/core/vaults/RVault.sol";
import "../../src/core/vaults/RMVault.sol";
import "../../src/strategies/YearnStrategy.sol";

contract PrepareUpgrade5Polygon is Script {
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

    function testDeployPolygon() external {}
}
