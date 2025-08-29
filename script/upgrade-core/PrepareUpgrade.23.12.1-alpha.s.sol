// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
import {Factory} from "../../src/core/Factory.sol";
import {Zap} from "../../src/core/Zap.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {RVault} from "../../src/core/vaults/RVault.sol";
import {RMVault} from "../../src/core/vaults/RMVault.sol";

contract PrepareUpgrade1 is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        address newImpl;

        newImpl = address(new Factory());
        console.log("Factory 1.0.1", newImpl);
        newImpl = address(new Zap());
        console.log("Zap 1.0.1", newImpl);

        newImpl = address(new CVault());
        console.log("CVault 1.0.1", newImpl);
        newImpl = address(new RVault());
        console.log("RVault 1.0.1", newImpl);
        newImpl = address(new RMVault());
        console.log("RMVault 1.0.1", newImpl);

        vm.stopBroadcast();
    }

    function testPrepareUpgrade() external {}
}
