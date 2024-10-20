// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "../../src/strategies/GammaUniswapV3MerklFarmStrategy.sol";
//import {StrategyDeveloperLib} from "../src/strategies/libs/StrategyDeveloperLib.sol";

contract DeployStrategyGUMFBase is Script {
    address public constant PLATFORM = 0x7eAeE5CfF17F7765d89F4A46b484256929C62312;
    /*address public constant GAMMA_UNISWAPV3_UNIPROXY = 0xbd8fD52BE2EC689dac9155FAd51774F63a965D99;
    address public constant GAMMA_UNISWAPV3_WETH_wstETH_100_PEGGED = 0xbC73A3247Eb976a0A29b22f19E4EBAfa45EfdC65;
    address public constant GAMMA_UNISWAPV3_cbETH_WETH_500_PEGGED = 0xa52ECC4ed16f97c71071A3Bd14309E846647d7F0;
    address public constant GAMMA_UNISWAPV3_USDC_USDT_100_STABLE = 0x96034EfF74c0D1ba2eCDBf4C09A6FE8FFd6b71c8;
    address public constant TOKEN_wstETH = 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452;
    address public constant TOKEN_UNI = 0xc3De830EA07524a0761646a6a4e4be0e114a3C83;
    address public constant TOKEN_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant POOL_UNISWAPV3_USDC_UNI_10000 = 0x35d84AE687f0D3bF8548d5470fd04D2abe74f074;*/

    function run() external {
        /*IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        ISwapper swapper = ISwapper(IPlatform(PLATFORM).swapper());
        IFactory.Farm[] memory farms = __farms();
        ISwapper.AddPoolData[] memory pools = _routes();*/

        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        /*address implementation = address(*/
        new GammaUniswapV3MerklFarmStrategy(); /*)*/

        /*swapper.addPools(pools, false);

        factory.addFarms(farms);

        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.GAMMA_UNISWAPV3_MERKL_FARM,
                implementation: implementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: type(uint).max
            }),
            StrategyDeveloperLib.getDeveloper(StrategyIdLib.GAMMA_UNISWAPV3_MERKL_FARM)
        );*/

        vm.stopBroadcast();
    }

    function testDeployBase() external {}

    /*    function _routes() internal pure returns (ISwapper.AddPoolData[] memory pools) {
        pools = new ISwapper.AddPoolData[](1);
        uint i;
        pools[i++] = _makePoolData(POOL_UNISWAPV3_USDC_UNI_10000, AmmAdapterIdLib.UNISWAPV3, TOKEN_UNI, TOKEN_USDC);
    }

    function __farms() internal view returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](3);
        uint i;
        _farms[i++] =
            _makeGammaUniswapV3MerklFarm(GAMMA_UNISWAPV3_cbETH_WETH_500_PEGGED, ALMPositionNameLib.PEGGED, TOKEN_UNI);
        _farms[i++] = _makeGammaUniswapV3MerklFarm(
            GAMMA_UNISWAPV3_WETH_wstETH_100_PEGGED, ALMPositionNameLib.PEGGED, TOKEN_wstETH
        );
        _farms[i++] =
            _makeGammaUniswapV3MerklFarm(GAMMA_UNISWAPV3_USDC_USDT_100_STABLE, ALMPositionNameLib.STABLE, TOKEN_UNI);
    }

    function _makeGammaUniswapV3MerklFarm(
        address hypervisor,
        uint preset,
        address rewardAsset
    ) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IHypervisor(hypervisor).pool();
        farm.strategyLogicId = StrategyIdLib.GAMMA_UNISWAPV3_MERKL_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = rewardAsset;
        farm.addresses = new address[](2);
        farm.addresses[0] = GAMMA_UNISWAPV3_UNIPROXY;
        farm.addresses[1] = hypervisor;
        farm.nums = new uint[](1);
        farm.nums[0] = preset;
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makePoolData(
        address pool,
        string memory ammAdapterId,
        address tokenIn,
        address tokenOut
    ) internal pure returns (ISwapper.AddPoolData memory) {
        return ISwapper.AddPoolData({pool: pool, ammAdapterId: ammAdapterId, tokenIn: tokenIn, tokenOut: tokenOut});
    }*/
}
