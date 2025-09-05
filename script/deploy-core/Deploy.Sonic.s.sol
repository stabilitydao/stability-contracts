// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {SonicLib} from "../../chains/sonic/SonicLib.sol";
import {DeployCore} from "../base/DeployCore.sol";

contract DeploySonic is Script, DeployCore {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address platform = _deployCore(SonicLib.platformDeployParams());
        SonicLib.deployAndSetupInfrastructure(platform, false);
        vm.stopBroadcast();
    }

    function testDeploySonic() external {}
}
