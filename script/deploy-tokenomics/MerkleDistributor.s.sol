// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {MerkleDistributor} from "../../src/tokenomics/MerkleDistributor.sol";

contract DeployMerkleDistributorImpl is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new MerkleDistributor();
        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
