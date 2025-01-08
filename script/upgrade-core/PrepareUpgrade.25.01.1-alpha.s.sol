// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/core/Zap.sol";

contract PrepareUpgrade7 is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Zap 1.0.3: bugfix for Ichi deposit
        new Zap();

        vm.stopBroadcast();
    }

    function testPrepareUpgrade() external {}
}
