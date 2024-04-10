// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../chains/PolygonLib.sol";
import "../src/strategies/IchiRetroMerklFarmStrategy.sol";

/// @dev Deploy script for operator
/// WARNING! This is bad practise because PolygonLib will be deployed too
contract DeployStrategyIRMFPolygon is Script {
    address public constant PLATFORM = 0xb2a0737ef27b5Cc474D24c779af612159b1c3e60;

    function run() external {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        // ISwapper swapper = ISwapper(IPlatform(PLATFORM).swapper());

        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        new IchiRetroMerklFarmStrategy();

        // farms
        factory.addFarms(PolygonLib.farms4());

        // swapper routes
        // swapper.addPools(PolygonLib.routes4(), false);

        vm.stopBroadcast();
    }

    function testDeployPolygon() external {}
}
