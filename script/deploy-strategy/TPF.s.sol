// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {TridentPearlFarmStrategy} from "../../src/strategies/TridentPearlFarmStrategy.sol";

contract DeployStrategyTPF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new TridentPearlFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
