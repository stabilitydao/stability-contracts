// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/strategies/IchiRetroMerklFarmStrategy.sol";
import "../src/strategies/GammaRetroMerklFarmStrategy.sol";

contract DeployUpdateRetroStrategiesPolygon is Script {
    address public constant PLATFORM = 0xb2a0737ef27b5Cc474D24c779af612159b1c3e60;
    address public constant POOL_RETRO_USDCe_CASH_100 = 0x619259F699839dD1498FFC22297044462483bD27;
    address public constant TOKEN_CASH = 0x5D066D022EDE10eFa2717eD3D79f22F949F8C175;
    address public constant TOKEN_USDCe = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;

    function run() external {
        ISwapper swapper = ISwapper(IPlatform(PLATFORM).swapper());

        // route
        ISwapper.AddPoolData[] memory pools = new ISwapper.AddPoolData[](1);
        pools[0] = ISwapper.AddPoolData({
            pool: POOL_RETRO_USDCe_CASH_100,
            ammAdapterId: AmmAdapterIdLib.UNISWAPV3,
            tokenIn: TOKEN_CASH,
            tokenOut: TOKEN_USDCe
        });

        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        swapper.addPools(pools, false);

        new IchiRetroMerklFarmStrategy();
        new GammaRetroMerklFarmStrategy();

        vm.stopBroadcast();
    }

    function testDeployPolygon() external {}
}
