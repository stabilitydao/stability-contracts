// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Script.sol";
import "../src/interfaces/IPlatform.sol";
import "../src/interfaces/IFactory.sol";
import "../src/core/libs/VaultTypeLib.sol";
import "../chains/PolygonLib.sol";

contract DeployPolygonForking is Script {
    function run() external {
        // default account 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
        uint deployerPrivateKey = vm.parseUint("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer", deployer);
        vm.startBroadcast(deployerPrivateKey);
        IPlatform platform = IPlatform(PolygonLib.runDeploy(true));
        IFactory factory = IFactory(platform.factory());
        address vaultImplementation;
        (, vaultImplementation,,,) = factory.vaultConfig(keccak256(bytes(VaultTypeLib.COMPOUNDING)));
        factory.setVaultConfig(
            IFactory.VaultConfig({
                vaultType: VaultTypeLib.COMPOUNDING,
                implementation: vaultImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                buildingPrice: 1e18
            })
        );
        (, vaultImplementation,,,) = factory.vaultConfig(keccak256(bytes(VaultTypeLib.REWARDING)));
        factory.setVaultConfig(
            IFactory.VaultConfig({
                vaultType: VaultTypeLib.REWARDING,
                implementation: vaultImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                buildingPrice: 1e18
            })
        );
        (, vaultImplementation,,,) = factory.vaultConfig(keccak256(bytes(VaultTypeLib.REWARDING_MANAGED)));
        factory.setVaultConfig(
            IFactory.VaultConfig({
                vaultType: VaultTypeLib.REWARDING_MANAGED,
                implementation: vaultImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                buildingPrice: 2e18
            })
        );
        platform.setInitialBoost(1e18, 10 * 86400);
        vm.stopBroadcast();
    }

    function testDeployPolygon() external {}
}
