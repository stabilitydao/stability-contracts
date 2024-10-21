// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../chains/BaseLib.sol";
import {DeployCore} from "../base/DeployCore.sol";

contract DeployBase is Script, DeployCore {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address platform = _deployCore(BaseLib.platformDeployParams());
        BaseLib.deployAndSetupInfrastructure(platform, false);
        vm.stopBroadcast();
    }

    function testDeployBase() external {}
}
