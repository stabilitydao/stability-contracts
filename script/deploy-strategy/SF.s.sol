// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/strategies/SwapXFarmStrategy.sol";

contract DeploySF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new SwapXFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
