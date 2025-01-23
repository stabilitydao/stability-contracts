// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/strategies/TridentPearlFarmStrategy.sol";

contract DeployStrategyTPF is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new TridentPearlFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployStrategy() external {}
}
