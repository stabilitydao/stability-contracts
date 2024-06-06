// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../chains/BaseLib.sol";

contract DeployBase is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        BaseLib.runDeploy(true);
        vm.stopBroadcast();
    }

    function testDeployPolygon() external {}
}
