// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/strategies/QuickSwapStaticMerklFarmStrategy.sol";

contract DeployStrategyQSMFPolygon is Script {
    address public constant PLATFORM = 0xb2a0737ef27b5Cc474D24c779af612159b1c3e60;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new QuickSwapStaticMerklFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployPolygon() external {}
}
