// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {GammaRetroMerklFarmStrategy} from "../../src/strategies/GammaRetroMerklFarmStrategy.sol";

contract DeployStrategyGRMF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new GammaRetroMerklFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
