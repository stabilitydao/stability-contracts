// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
//import "../src/core/proxy/Proxy.sol";
//import "../src/adapters/CurveAdapter.sol";
import "../../src/strategies/CurveConvexFarmStrategy.sol";

contract DeployStrategyCCFPolygon is Script {
    address public constant PLATFORM = 0xb2a0737ef27b5Cc474D24c779af612159b1c3e60;
    /*address public constant POOL_CURVE_crvUSD_USDCe = 0x864490Cf55dc2Dee3f0ca4D06F5f80b2BB154a03;
    address public constant POOL_CURVE_crvUSD_USDT = 0xA70Af99bFF6b168327f9D1480e29173e757c7904;
    address public constant POOL_CURVE_crvUSD_DAI = 0x62c949ee985b125Ff2d7ddcf4Fe7AEcB0a040E2a;
    address public constant POOL_CURVE_crvUSD_USDC = 0x5225010A0AE133B357861782B0B865a48471b2C5;
    address public constant POOL_QUICKSWAPV3_CRV_WMATIC = 0x00A6177C6455A29B8dAa7144B2bEfc9F2147BB7E;
    address public constant TOKEN_crvUSD = 0xc4Ce1D6F5D98D65eE25Cf85e9F2E9DcFEe6Cb5d6;
    address public constant TOKEN_CRV = 0x172370d5Cd63279eFa6d502DAB29171933a610AF;
    address public constant TOKEN_WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public constant TOKEN_USDCe = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address public constant CONVEX_REWARD_POOL_crvUSD_USDCe = 0xBFEE9F3E015adC754066424AEd535313dc764116;
    address public constant CONVEX_REWARD_POOL_crvUSD_USDT = 0xd2D8BEB901f90163bE4667A85cDDEbB7177eb3E3;
    address public constant CONVEX_REWARD_POOL_crvUSD_DAI = 0xaCb744c7e7C95586DB83Eda3209e6483Fb1FCbA4;
    address public constant CONVEX_REWARD_POOL_crvUSD_USDC = 0x11F2217fa1D5c44Eae310b9b985E2964FC47D8f9;
    address public constant DEV = 0x88888887C3ebD4a33E34a15Db4254C74C75E5D4A;*/

    function run() external {
        /*// prepare pools
        ISwapper swapper = ISwapper(IPlatform(PLATFORM).swapper());
        ISwapper.AddPoolData[] memory pools = new ISwapper.AddPoolData[](2);
        pools[0] = ISwapper.AddPoolData({
            pool: POOL_CURVE_crvUSD_USDCe,
            ammAdapterId: AmmAdapterIdLib.CURVE,
            tokenIn: TOKEN_crvUSD,
            tokenOut: TOKEN_USDCe
        });
        pools[1] = ISwapper.AddPoolData({
            pool: POOL_QUICKSWAPV3_CRV_WMATIC,
            ammAdapterId: AmmAdapterIdLib.ALGEBRA,
            tokenIn: TOKEN_CRV,
            tokenOut: TOKEN_WMATIC
        });

        // prepare thresholds
        address[] memory tokenIn = new address[](2);
        tokenIn[0] = TOKEN_CRV;
        tokenIn[1] = TOKEN_crvUSD;
        uint[] memory thresholdAmount = new uint[](2);
        thresholdAmount[0] = 1e15;
        thresholdAmount[1] = 1e15;

        // prepare farms
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        IFactory.Farm[] memory _farms = new IFactory.Farm[](4);
        uint i;
        _farms[i++] = _makeCurveConvexFarm(POOL_CURVE_crvUSD_USDCe, CONVEX_REWARD_POOL_crvUSD_USDCe);
        _farms[i++] = _makeCurveConvexFarm(POOL_CURVE_crvUSD_USDT, CONVEX_REWARD_POOL_crvUSD_USDT);
        _farms[i++] = _makeCurveConvexFarm(POOL_CURVE_crvUSD_DAI, CONVEX_REWARD_POOL_crvUSD_DAI);
        _farms[i++] = _makeCurveConvexFarm(POOL_CURVE_crvUSD_USDC, CONVEX_REWARD_POOL_crvUSD_USDC);;
        */

        // start deploy
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        /*// add AMM adapter
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new CurveAdapter()));
        IPlatform(PLATFORM).addAmmAdapter(AmmAdapterIdLib.CURVE, address(proxy));*/

        // deploy strategy implementation
        /*address implementation = address(*/
        new CurveConvexFarmStrategy(); /*)*/

        /*// add routes and thresholds
        swapper.addPools(pools, false);
        swapper.setThresholds(tokenIn, thresholdAmount);

        // add farms
        factory.addFarms(_farms);

        // set config
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.CURVE_CONVEX_FARM,
                implementation: implementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: type(uint).max
            }),
            DEV
        );*/

        vm.stopBroadcast();
    }

    function testDeployPolygon() external {}

    /*

    function _makeCurveConvexFarm(
        address curvePool,
        address convexRewardPool
    ) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        uint rewardTokensLength = IConvexRewardPool(convexRewardPool).rewardLength();
        farm.status = 0;
        // pool address can be extracted from convexRewardPool here: curveGauge() -> lp_token()
        farm.pool = curvePool;
        farm.strategyLogicId = StrategyIdLib.CURVE_CONVEX_FARM;
        farm.rewardAssets = new address[](rewardTokensLength);
        for (uint i; i < rewardTokensLength; ++i) {
            IConvexRewardPool.RewardType memory r = IConvexRewardPool(convexRewardPool).rewards(i);
            farm.rewardAssets[i] = r.reward_token;
        }
        farm.addresses = new address[](1);
        farm.addresses[0] = convexRewardPool;
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }*/
}
