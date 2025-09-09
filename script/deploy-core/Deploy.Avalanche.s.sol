// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {AvalancheLib} from "../../chains/avalanche/AvalancheLib.sol";
import {DeployCore} from "../base/DeployCore.sol";

contract DeployAvalanche is Script, DeployCore {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address platform = _deployCore(AvalancheLib.platformDeployParams());
        AvalancheLib.deployAndSetupInfrastructure(platform);
        vm.stopBroadcast();
    }

    function testDeployAvalanche() external {}
}
