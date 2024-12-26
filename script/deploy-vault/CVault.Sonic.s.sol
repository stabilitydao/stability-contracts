// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/core/vaults/CVault.sol";

contract DeployCVaultSonic is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new CVault();
        vm.stopBroadcast();
    }

    function testDeploySonic() external {}
}
