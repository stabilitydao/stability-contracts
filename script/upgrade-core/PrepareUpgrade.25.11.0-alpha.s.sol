// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Script} from "forge-std/Script.sol";
import {Recovery} from "../../src/tokenomics/Recovery.sol";
import {Platform} from "../../src/core/Platform.sol";

contract PrepareUpgrade25110alpha is Script {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Recovery 1.2.2
        new Recovery();

        // Platform 1.6.4
        new Platform();

        vm.stopBroadcast();
    }

    function testPrepareUpgrade() external {}
}
