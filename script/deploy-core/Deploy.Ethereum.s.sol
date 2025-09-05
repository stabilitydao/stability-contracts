// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {EthereumLib} from "../../chains/EthereumLib.sol";
import {DeployCore} from "../base/DeployCore.sol";

contract DeployEthereum is Script, DeployCore {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address platform = _deployCore(EthereumLib.platformDeployParams());
        EthereumLib.deployAndSetupInfrastructure(platform, false);
        vm.stopBroadcast();
    }

    function testDeployEthereum() external {}
}
