// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../chains/ArbitrumLib.sol";
import {DeployCore} from "../base/DeployCore.sol";

contract DeployArbitrum is Script, DeployCore {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address platform = _deployCore(ArbitrumLib.platformDeployParams());
        ArbitrumLib.deployAndSetupInfrastructure(platform, false);
        vm.stopBroadcast();
    }

    function testDeployArbitrum() external {}
}
