// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/strategies/CompoundFarmStrategy.sol";

contract DeployCF is Script {
    address public constant PLATFORM = 0xb2a0737ef27b5Cc474D24c779af612159b1c3e60;
    //    address public constant COMPOUND_COMET = 0xF25212E676D1F7F89Cd72fFEe66158f541246445;
    //    address public constant COMPOUND_COMET_REWARDS = 0x45939657d1CA34A8FA39A924B71D28Fe8431e581;
    //    address public constant TOKEN_WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    //    address public constant TOKEN_COMP = 0x8505b9d2254A7Ae468c0E9dd10Ccea3A837aef5c;
    //    address public constant POOL_UNISWAPV3_WETH_COMP_3000 = 0x2260E0081A2A042DC55A07D379eb3c18bE28A1F2;
    //    string public constant UNISWAPV3 = "UniswapV3";

    function run() external {
        //        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        //        ISwapper swapper = ISwapper(IPlatform(PLATFORM).swapper());
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new CompoundFarmStrategy();

        /*ISwapper.AddPoolData[] memory pools = new ISwapper.AddPoolData[](1);
        pools[0] = ISwapper.AddPoolData({
            pool: POOL_UNISWAPV3_WETH_COMP_3000,
            ammAdapterId: UNISWAPV3,
            tokenIn: TOKEN_COMP,
            tokenOut: TOKEN_WETH
        });
        swapper.addPools(pools, false);
        address[] memory tokenIn = new address[](1);
        tokenIn[0] = TOKEN_COMP;
        uint[] memory thresholdAmount = new uint[](1);
        thresholdAmount[0] = 1e15;
        swapper.setThresholds(tokenIn, thresholdAmount);

        IFactory.Farm[] memory _farms = new IFactory.Farm[](1);
        address[] memory rewardAssets;
        address[] memory addresses;
        uint[] memory nums;
        int24[] memory ticks;
        // [18]
        rewardAssets = new address[](1);
        rewardAssets[0] = TOKEN_COMP;
        addresses = new address[](2);
        addresses[0] = COMPOUND_COMET;
        addresses[1] = COMPOUND_COMET_REWARDS;
        nums = new uint[](0);
        ticks = new int24[](0);
        _farms[0] = IFactory.Farm({
            status: 0,
            pool: address(0),
            strategyLogicId: StrategyIdLib.COMPOUND_FARM,
            rewardAssets: rewardAssets,
            addresses: addresses,
            nums: nums,
            ticks: ticks
        });
        factory.addFarms(_farms);*/

        vm.stopBroadcast();
    }

    function testDeployPolygon() external {}
}
