// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {PlasmaLib} from "../../chains/plasma/PlasmaLib.sol";
import {DeployCore} from "../base/DeployCore.sol";

contract DeployPlasma is Script, DeployCore {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address platform = _deployCore(PlasmaLib.platformDeployParams());
        PlasmaLib.deployAndSetupInfrastructure(platform);
        vm.stopBroadcast();
    }

    function testDeployCore() external {}
}
