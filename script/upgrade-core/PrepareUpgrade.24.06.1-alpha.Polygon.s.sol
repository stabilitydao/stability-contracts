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

        // Factory 1.1.1: reduced factory size. moved upgradeStrategyProxy, upgradeVaultProxy logic to FactoryLib
        new Factory();

        vm.stopBroadcast();
    }

    function testDeployPolygon() external {}
}
