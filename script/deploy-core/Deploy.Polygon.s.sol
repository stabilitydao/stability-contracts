// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../chains/PolygonLib.sol";
import {DeployCore} from "../base/DeployCore.sol";

contract DeployPolygon is Script, DeployCore {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address platform = _deployCore(PolygonLib.platformDeployParams());
        PolygonLib.deployAndSetupInfrastructure(platform, false);
        vm.stopBroadcast();
    }

    function testDeployPolygon() external {}
}
