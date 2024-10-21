// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/strategies/CompoundFarmStrategy.sol";

contract DeployCFBase is Script {
    address public constant PLATFORM = 0x7eAeE5CfF17F7765d89F4A46b484256929C62312;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new CompoundFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployPolygon() external {}
}
