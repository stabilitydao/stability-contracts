// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../src/strategies/IchiRetroMerklFarmStrategy.sol";

/// @dev Deploy script for operator
contract DeployUpdateStrategyIRMFPolygon is Script {
    address public constant PLATFORM = 0xb2a0737ef27b5Cc474D24c779af612159b1c3e60;
    address public constant TOKEN_oRETRO = 0x3A29CAb2E124919d14a6F735b6033a3AaD2B260F;
    address public constant ICHI_RETRO_WMATIC_WETH_ETH = 0xE9BD439259DE0347DC26B86b3E73437E93858283;
    address public constant ICHI_RETRO_WMATIC_USDCe_USDC = 0x5Ef5630195164956d394fF8093C1B6964cb5814B;
    address public constant ICHI_RETRO_WBTC_WETH_ETH = 0x0B0302014DD4FB6A77da03bF9034db5FEcB68eA8;
    address public constant POOL_RETRO_WBTC_WETH_500 = 0xb694E3bdd4BCdF843510983D257679D1E627C474;
    address public constant POOL_RETRO_WMATIC_WETH_500 = 0x1a34EaBbe928Bf431B679959379b2225d60D9cdA;
    address public constant POOL_RETRO_WMATIC_USDCe_500 = 0xEC15624FBB314eb05BaaD4cA49b7904C0Cb6b645;

    function run() external {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        IFactory.Farm[] memory _farms = _farms5();

        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // v 1.0.1 with bugfix
        new IchiRetroMerklFarmStrategy();

        // farms
        factory.addFarms(_farms);

        vm.stopBroadcast();
    }

    function testDeployPolygon() external {}

    function _farms5() internal pure returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](3);
        address[] memory rewardAssets;
        address[] memory addresses;
        uint[] memory nums;
        int24[] memory ticks;

        // [26]
        rewardAssets = new address[](1);
        rewardAssets[0] = TOKEN_oRETRO;
        addresses = new address[](1);
        addresses[0] = ICHI_RETRO_WMATIC_WETH_ETH;
        nums = new uint[](0);
        ticks = new int24[](0);
        _farms[0] = IFactory.Farm({
            status: 0,
            pool: POOL_RETRO_WMATIC_WETH_500,
            strategyLogicId: StrategyIdLib.ICHI_RETRO_MERKL_FARM,
            rewardAssets: rewardAssets,
            addresses: addresses,
            nums: nums,
            ticks: ticks
        });

        // [27]
        rewardAssets = new address[](1);
        rewardAssets[0] = TOKEN_oRETRO;
        addresses = new address[](1);
        addresses[0] = ICHI_RETRO_WMATIC_USDCe_USDC;
        nums = new uint[](0);
        ticks = new int24[](0);
        _farms[1] = IFactory.Farm({
            status: 0,
            pool: POOL_RETRO_WMATIC_USDCe_500,
            strategyLogicId: StrategyIdLib.ICHI_RETRO_MERKL_FARM,
            rewardAssets: rewardAssets,
            addresses: addresses,
            nums: nums,
            ticks: ticks
        });

        // [28]
        rewardAssets = new address[](1);
        rewardAssets[0] = TOKEN_oRETRO;
        addresses = new address[](1);
        addresses[0] = ICHI_RETRO_WBTC_WETH_ETH;
        nums = new uint[](0);
        ticks = new int24[](0);
        _farms[2] = IFactory.Farm({
            status: 0,
            pool: POOL_RETRO_WBTC_WETH_500,
            strategyLogicId: StrategyIdLib.ICHI_RETRO_MERKL_FARM,
            rewardAssets: rewardAssets,
            addresses: addresses,
            nums: nums,
            ticks: ticks
        });
    }
}
