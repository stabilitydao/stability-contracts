// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/strategies/IchiQuickSwapMerklFarmStrategy.sol";
import "../src/strategies/IchiRetroMerklFarmStrategy.sol";

contract DeployUpdateStrategyIQMFPolygon is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        new IchiQuickSwapMerklFarmStrategy();
        new IchiRetroMerklFarmStrategy();

        vm.stopBroadcast();
    }

    function testDeployPolygon() external {}
}
