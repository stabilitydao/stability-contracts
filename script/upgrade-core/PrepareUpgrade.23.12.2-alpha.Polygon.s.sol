// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/adapters/AlgebraAdapter.sol";
import "../../src/adapters/UniswapV3Adapter.sol";
import "../../src/adapters/KyberAdapter.sol";
import "../../src/core/Zap.sol";
// import "../../src/strategies/QuickswapV3StaticFarmStrategy.sol";

contract PrepareUpgrade2Polygon is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new AlgebraAdapter();
        new UniswapV3Adapter();
        new KyberAdapter();
        new Zap();
        // new QuickSwapV3StaticFarmStrategy();
        vm.stopBroadcast();
    }

    function testDeployPolygon() external {}
}
