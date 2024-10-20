// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";
import "forge-std/Script.sol";
import "../../chains/PolygonLib.sol";
import "../../src/core/Factory.sol";
import "../../src/core/Zap.sol";
import "../../src/core/vaults/CVault.sol";
import "../../src/core/vaults/RVault.sol";
import "../../src/core/vaults/RMVault.sol";

contract PrepareUpgrade1Polygon is Script {
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

    function testDeployPolygon() external {}
}
