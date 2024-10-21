// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/core/Factory.sol";
import "../../src/adapters/AlgebraAdapter.sol";
import "../../src/adapters/UniswapV3Adapter.sol";
import "../../src/adapters/KyberAdapter.sol";
import "../../src/strategies/DefiEdgeQuickSwapMerklFarmStrategy.sol";

contract PrepareUpgrade4Polygon is Script {
    address public constant PLATFORM = 0xb2a0737ef27b5Cc474D24c779af612159b1c3e60;
    address public constant TOKEN_dQUICK = 0x958d208Cdf087843e9AD98d23823d32E17d723A1;
    address public constant DEFIEDGE_STRATEGY_WMATIC_WETH_NARROW_1 = 0xd778C83E7cA19c2217d98daDACf7fD03B79B18cB;
    address public constant DEFIEDGE_STRATEGY_WMATIC_WETH_NARROW_2 = 0x07d82761C3527Caf190b946e13d5C11291194aE6;
    address public constant POOL_QUICKSWAPV3_WMATIC_WETH = 0x479e1B71A702a595e19b6d5932CD5c863ab57ee0;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new Factory();
        new AlgebraAdapter();
        new UniswapV3Adapter();
        new KyberAdapter();
        new DefiEdgeQuickSwapMerklFarmStrategy();

        // new farms for DQMF
        IFactory.Farm[] memory _farms = new IFactory.Farm[](2);
        address[] memory rewardAssets;
        address[] memory addresses;
        uint[] memory nums;
        int24[] memory ticks;
        // [19]
        rewardAssets = new address[](1);
        rewardAssets[0] = TOKEN_dQUICK;
        addresses = new address[](1);
        addresses[0] = DEFIEDGE_STRATEGY_WMATIC_WETH_NARROW_1;
        nums = new uint[](1);
        nums[0] = 0; // NARROW
        ticks = new int24[](0);
        _farms[0] = IFactory.Farm({
            status: 0,
            pool: POOL_QUICKSWAPV3_WMATIC_WETH,
            strategyLogicId: StrategyIdLib.DEFIEDGE_QUICKSWAP_MERKL_FARM,
            rewardAssets: rewardAssets,
            addresses: addresses,
            nums: nums,
            ticks: ticks
        });

        // [20]
        rewardAssets = new address[](1);
        rewardAssets[0] = TOKEN_dQUICK;
        addresses = new address[](1);
        addresses[0] = DEFIEDGE_STRATEGY_WMATIC_WETH_NARROW_2;
        nums = new uint[](1);
        nums[0] = 0; // NARROW
        ticks = new int24[](0);
        _farms[1] = IFactory.Farm({
            status: 0,
            pool: POOL_QUICKSWAPV3_WMATIC_WETH,
            strategyLogicId: StrategyIdLib.DEFIEDGE_QUICKSWAP_MERKL_FARM,
            rewardAssets: rewardAssets,
            addresses: addresses,
            nums: nums,
            ticks: ticks
        });

        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        factory.addFarms(_farms);

        vm.stopBroadcast();
    }

    function testDeployPolygon() external {}
}
