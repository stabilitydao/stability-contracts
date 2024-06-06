// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../src/core/proxy/Proxy.sol";
import "../src/adapters/libs/AmmAdapterIdLib.sol";
import "../src/adapters/ChainlinkAdapter.sol";
import "../src/strategies/libs/StrategyIdLib.sol";
import "../src/strategies/libs/ALMPositionNameLib.sol";
import "../src/interfaces/IFactory.sol";
import "../src/interfaces/IPlatform.sol";
import "../src/interfaces/ISwapper.sol";
import "../src/integrations/convex/IConvexRewardPool.sol";
import "../script/libs/DeployLib.sol";
import "../script/libs/DeployAdapterLib.sol";
import "../script/libs/DeployStrategyLib.sol";

/// @dev Addresses, routes, farms, strategy logics, reward tokens, deploy function and other data for Base network
library BaseLib {
    // initial addresses
    address public constant MULTISIG = 0x626Bd898ca994c11c9014377f4c50d30f2B0006c; // team

    // ERC20
    address public constant TOKEN_WETH = 0x4200000000000000000000000000000000000006;
    address public constant TOKEN_wstETH = 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452;
    address public constant TOKEN_cbETH = 0x2Ae3F1Ec7F1F5012CFEab0185bfc7aa3cf0DEc22;
    address public constant TOKEN_sfrxETH = 0x1f55a02A049033E3419a8E2975cF3F572F4e6E9A;
    address public constant TOKEN_USDT = 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2;
    address public constant TOKEN_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant TOKEN_USDbC = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;
    address public constant TOKEN_sFRAX = 0xe4796cCB6bB5DE2290C417Ac337F2b66CA2E770E;
    address public constant TOKEN_COMP = 0x9e1028F5F1D5eDE59748FFceE5532509976840E0;

    // AMMs
    address public constant POOL_UNISWAPV3_WETH_USDT_500 = 0xd92E0767473D1E3FF11Ac036f2b1DB90aD0aE55F;
    address public constant POOL_UNISWAPV3_WETH_USDC_500 = 0xd0b53D9277642d899DF5C87A3966A349A798F224;
    address public constant POOL_UNISWAPV3_WETH_wstETH_100 = 0x20E068D76f9E90b90604500B84c7e19dCB923e7e;
    address public constant POOL_UNISWAPV3_cbETH_WETH_500 = 0x10648BA41B8565907Cfa1496765fA4D95390aa0d;
    address public constant POOL_UNISWAPV3_USDC_USDT_100 = 0xD56da2B74bA826f19015E6B7Dd9Dae1903E85DA1;
    address public constant POOL_UNISWAPV3_USDC_wstETH_500 = 0x45837e65E4c44cA260aB40E6dc30fF1B466a00cA;
    address public constant POOL_UNISWAPV3_WETH_COMP_10000 = 0x3367fEDd8Ad5a8Cf01cFE89Df3c697D3A59A1cAD;
    address public constant POOL_BASESWAP_WETH_USDC_450 = 0x883e4AE0A817f2901500971B353b5dD89Aa52184;
    address public constant POOL_BASESWAP_USDC_USDbC_80 = 0x88492051E18a65FE00241A93699A6082aE95c828;
    address public constant POOL_BASESWAP_sfrxETH_WETH_80 = 0x19F5828aA11e12Eed05Bfb435857115bd098823a;
    address public constant POOL_BASESWAP_WETH_USDbC_450 = 0xEf3C164b0feE8Eb073513E88EcEa280A58cC9945;
    address public constant POOL_BASESWAP_USDC_sFRAX_80 = 0x74E65d5E7f820771aa86fc99e5d67578Dc77517a;
    address public constant POOL_BASESWAP_sfrxETH_sFRAX_450 = 0xee8092F8Da8342a07076b820d8bB553E962c182b;

    // Oracles
    address public constant ORACLE_CHAINLINK_USDC_USD = 0x7e860098F58bBFC8648a4311b374B1D669a2bc6B;
    address public constant ORACLE_CHAINLINK_cbETH_USD = 0xd7818272B9e248357d13057AAb0B417aF31E817d;
    address public constant ORACLE_CHAINLINK_ETH_USD = 0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70;

    // Compound
    address public constant COMPOUND_COMET_ETH = 0x46e6b214b524310239732D51387075E0e70970bf;
    address public constant COMPOUND_COMET_USDC = 0xb125E6687d4313864e53df431d5425969c15Eb2F;
    address public constant COMPOUND_COMET_USDbC = 0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf;
    address public constant COMPOUND_COMET_REWARDS = 0x123964802e6ABabBE1Bc9547D72Ef1B69B00A6b1;

    // DeX aggregators
    address public constant ONE_INCH = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    function runDeploy(bool showLog) internal returns (address platform) {
        //region ----- Deploy Platform -----
        uint[] memory buildingPrice = new uint[](1);
        buildingPrice[0] = 100e6;
        platform = DeployLib.deployPlatform(
            "24.06.0-alpha",
            MULTISIG,
            address(0),
            TOKEN_USDC,
            buildingPrice,
            "Base",
            CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x2356f0), bytes3(0x000000))),
            TOKEN_USDC,
            address(0),
            1e16,
            2e16
        );
        if (showLog) {
            console.log("Deployed Stability platform", IPlatform(platform).platformVersion());
            console.log("Platform address: ", platform);
        }
        //endregion -- Deploy Platform ----

        //region ----- Deploy and setup oracle adapters -----
        IPriceReader priceReader = PriceReader(IPlatform(platform).priceReader());
        // Chainlink
        {
            Proxy proxy = new Proxy();
            proxy.initProxy(address(new ChainlinkAdapter()));
            ChainlinkAdapter chainlinkAdapter = ChainlinkAdapter(address(proxy));
            chainlinkAdapter.initialize(platform);
            address[] memory assets = new address[](3);
            assets[0] = TOKEN_USDC;
            assets[1] = TOKEN_WETH;
            assets[2] = TOKEN_cbETH;
            address[] memory priceFeeds = new address[](3);
            priceFeeds[0] = ORACLE_CHAINLINK_USDC_USD;
            priceFeeds[1] = ORACLE_CHAINLINK_ETH_USD;
            priceFeeds[2] = ORACLE_CHAINLINK_cbETH_USD;
            chainlinkAdapter.addPriceFeeds(assets, priceFeeds);
            priceReader.addAdapter(address(chainlinkAdapter));
            DeployLib.logDeployAndSetupOracleAdapter("ChainLink", address(chainlinkAdapter), showLog);
        }
        //endregion -- Deploy and setup oracle adapters -----

        //region ----- Deploy AMM adapters -----
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.UNISWAPV3);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.CURVE);
        DeployLib.logDeployAmmAdapters(platform, showLog);
        //endregion -- Deploy AMM adapters ----

        //region ----- Setup Swapper -----
        {
            (ISwapper.AddPoolData[] memory bcPools, ISwapper.AddPoolData[] memory pools) = routes();
            ISwapper swapper = ISwapper(IPlatform(platform).swapper());
            swapper.addBlueChipsPools(bcPools, false);
            swapper.addPools(pools, false);
            address[] memory tokenIn = new address[](8);
            tokenIn[0] = TOKEN_USDC;
            tokenIn[1] = TOKEN_USDT;
            tokenIn[2] = TOKEN_WETH;
            tokenIn[3] = TOKEN_wstETH;
            tokenIn[4] = TOKEN_sfrxETH;
            tokenIn[5] = TOKEN_USDbC;
            tokenIn[6] = TOKEN_sFRAX;
            tokenIn[7] = TOKEN_cbETH;
            uint[] memory thresholdAmount = new uint[](8);
            thresholdAmount[0] = 1e3;
            thresholdAmount[1] = 1e3;
            thresholdAmount[2] = 1e15;
            thresholdAmount[3] = 1e15;
            thresholdAmount[4] = 1e15;
            thresholdAmount[5] = 1e3;
            thresholdAmount[6] = 1e15;
            thresholdAmount[7] = 1e15;
            swapper.setThresholds(tokenIn, thresholdAmount);
            DeployLib.logSetupSwapper(platform, showLog);
        }
        //endregion -- Setup Swapper -----

        //region ----- Add farms -----
        IFactory factory = IFactory(IPlatform(platform).factory());
        factory.addFarms(farms());
        DeployLib.logAddedFarms(address(factory), showLog);
        //endregion -- Add farms -----

        //region ----- Deploy strategy logics -----
        DeployStrategyLib.deployStrategy(platform, StrategyIdLib.COMPOUND_FARM, true);
        DeployLib.logDeployStrategies(platform, showLog);
        //endregion -- Deploy strategy logics -----

        //region ----- Add DeX aggregators -----
        address[] memory dexAggRouter = new address[](1);
        dexAggRouter[0] = ONE_INCH;
        IPlatform(platform).addDexAggregators(dexAggRouter);
        //endregion -- Add DeX aggregators -----
    }

    function routes()
        public
        pure
        returns (ISwapper.AddPoolData[] memory bcPools, ISwapper.AddPoolData[] memory pools)
    {
        //region ----- BC pools ----
        bcPools = new ISwapper.AddPoolData[](2);
        bcPools[0] = _makePoolData(POOL_UNISWAPV3_USDC_USDT_100, AmmAdapterIdLib.UNISWAPV3, TOKEN_USDC, TOKEN_USDT);
        bcPools[1] = _makePoolData(POOL_UNISWAPV3_WETH_USDC_500, AmmAdapterIdLib.UNISWAPV3, TOKEN_WETH, TOKEN_USDC);
        //endregion -- BC pools ----

        //region ----- Pools ----
        pools = new ISwapper.AddPoolData[](9);
        uint i;
        // UniswapV3
        pools[i++] = _makePoolData(POOL_UNISWAPV3_USDC_USDT_100, AmmAdapterIdLib.UNISWAPV3, TOKEN_USDC, TOKEN_USDT);
        pools[i++] = _makePoolData(POOL_UNISWAPV3_WETH_USDC_500, AmmAdapterIdLib.UNISWAPV3, TOKEN_WETH, TOKEN_USDC);
        pools[i++] = _makePoolData(POOL_UNISWAPV3_WETH_USDT_500, AmmAdapterIdLib.UNISWAPV3, TOKEN_USDT, TOKEN_WETH);
        pools[i++] = _makePoolData(POOL_UNISWAPV3_WETH_wstETH_100, AmmAdapterIdLib.UNISWAPV3, TOKEN_wstETH, TOKEN_WETH);
        pools[i++] = _makePoolData(POOL_UNISWAPV3_cbETH_WETH_500, AmmAdapterIdLib.UNISWAPV3, TOKEN_cbETH, TOKEN_WETH);
        pools[i++] = _makePoolData(POOL_UNISWAPV3_WETH_COMP_10000, AmmAdapterIdLib.UNISWAPV3, TOKEN_COMP, TOKEN_WETH);

        // BaseSwap
        pools[i++] = _makePoolData(POOL_BASESWAP_USDC_USDbC_80, AmmAdapterIdLib.UNISWAPV3, TOKEN_USDbC, TOKEN_USDC);
        pools[i++] = _makePoolData(POOL_BASESWAP_USDC_sFRAX_80, AmmAdapterIdLib.UNISWAPV3, TOKEN_sFRAX, TOKEN_USDC);
        pools[i++] = _makePoolData(POOL_BASESWAP_sfrxETH_WETH_80, AmmAdapterIdLib.UNISWAPV3, TOKEN_sfrxETH, TOKEN_WETH);
        //endregion -- Pools ----
    }

    function farms() public pure returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](3);
        uint i;

        // [0]-[2]
        _farms[i++] = _makeCompoundFarm(COMPOUND_COMET_USDC);
        _farms[i++] = _makeCompoundFarm(COMPOUND_COMET_USDbC);
        _farms[i++] = _makeCompoundFarm(COMPOUND_COMET_ETH);
    }

    function _makePoolData(
        address pool,
        string memory ammAdapterId,
        address tokenIn,
        address tokenOut
    ) internal pure returns (ISwapper.AddPoolData memory) {
        return ISwapper.AddPoolData({pool: pool, ammAdapterId: ammAdapterId, tokenIn: tokenIn, tokenOut: tokenOut});
    }

    function _makeCompoundFarm(address comet) internal pure returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.strategyLogicId = StrategyIdLib.COMPOUND_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = TOKEN_COMP;
        farm.addresses = new address[](2);
        farm.addresses[0] = comet;
        farm.addresses[1] = COMPOUND_COMET_REWARDS;
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    function testChainLib() external {}
}
