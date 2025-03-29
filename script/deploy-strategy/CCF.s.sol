// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {CurveConvexFarmStrategy} from "../../src/strategies/CurveConvexFarmStrategy.sol";

contract DeployStrategyCCF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new CurveConvexFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
