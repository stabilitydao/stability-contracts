// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {FeeTreasury} from "../../src/tokenomics/FeeTreasury.sol";

contract PrepareUpgrade25121alpha is Script {
    uint internal constant SONIC_CHAIN_ID = 146;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // FeeTreasury 1.1.1
        new FeeTreasury();

        vm.stopBroadcast();
    }

    function testPrepareUpgrade() external {}
}
