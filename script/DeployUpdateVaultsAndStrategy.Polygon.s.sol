// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/strategies/DefiEdgeQuickSwapMerklFarmStrategy.sol";
import "../src/strategies/GammaQuickSwapMerklFarmStrategy.sol";
import "../src/strategies/IchiRetroMerklFarmStrategy.sol";
import "../src/strategies/IchiQuickSwapMerklFarmStrategy.sol";
import "../src/strategies/QuickSwapStaticMerklFarmStrategy.sol";
import "../src/strategies/CompoundFarmStrategy.sol";
import "../src/core/vaults/CVault.sol";
import "../src/core/vaults/RVault.sol";
import "../src/core/vaults/RMVault.sol";

contract DeployUpdateVaultsAndStrategiesPolygon is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        new DefiEdgeQuickSwapMerklFarmStrategy();
        new GammaQuickSwapMerklFarmStrategy();
        new IchiRetroMerklFarmStrategy();
        new IchiQuickSwapMerklFarmStrategy();
        new QuickSwapStaticMerklFarmStrategy();
        new CompoundFarmStrategy();
        new CVault();
        new RVault();
        new RMVault();

        vm.stopBroadcast();
    }

    function testDeployPolygon() external {}
}
