// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/strategies/GammaQuickSwapMerklFarmStrategy.sol";

contract DeployUpdateStrategyGQMFPolygon is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        new GammaQuickSwapMerklFarmStrategy();

        vm.stopBroadcast();
    }

    function testDeployPolygon() external {}
}
