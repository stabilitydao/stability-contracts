// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {GammaUniswapV3MerklFarmStrategy} from "../../src/strategies/GammaUniswapV3MerklFarmStrategy.sol";

contract DeployStrategyGUMF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new GammaUniswapV3MerklFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
