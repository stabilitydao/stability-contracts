// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/strategies/BeetsWeightedFarm.sol";

contract DeployBWF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new BeetsWeightedFarm();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
