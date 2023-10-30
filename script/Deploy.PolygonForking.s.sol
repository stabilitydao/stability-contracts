// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Script.sol";
import "../src/interfaces/IPlatform.sol";
import "../src/interfaces/IFactory.sol";
import "../src/core/libs/VaultTypeLib.sol";
import "../chains/PolygonLib.sol";

contract DeployPolygonForking is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        // address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);
        IPlatform platform = IPlatform(PolygonLib.runDeploy(true));
        IFactory factory = IFactory(platform.factory());
        address vaultImplementation;
        (,vaultImplementation,,,) = factory.vaultConfig(keccak256(bytes(VaultTypeLib.COMPOUNDING)));
        factory.setVaultConfig(IFactory.VaultConfig({
            vaultType: VaultTypeLib.COMPOUNDING,
            implementation: vaultImplementation,
            deployAllowed: true,
            upgradeAllowed: true,
            buildingPrice: 1e18
        }));
        (,vaultImplementation,,,) = factory.vaultConfig(keccak256(bytes(VaultTypeLib.REWARDING)));
        factory.setVaultConfig(IFactory.VaultConfig({
            vaultType: VaultTypeLib.REWARDING,
            implementation: vaultImplementation,
            deployAllowed: true,
            upgradeAllowed: true,
            buildingPrice: 1e18
        }));
        (,vaultImplementation,,,) = factory.vaultConfig(keccak256(bytes(VaultTypeLib.REWARDING_MANAGED)));
        factory.setVaultConfig(IFactory.VaultConfig({
            vaultType: VaultTypeLib.REWARDING_MANAGED,
            implementation: vaultImplementation,
            deployAllowed: true,
            upgradeAllowed: true,
            buildingPrice: 2e18
        }));
        vm.stopBroadcast();
    }

    function testDeployPolygon() external {}
}
