// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../script/libs/LogDeployLib.sol";
import {IPlatformDeployer} from "../src/interfaces/IPlatformDeployer.sol";
import {IBalancerAdapter} from "../src/interfaces/IBalancerAdapter.sol";
import {CommonLib} from "../src/core/libs/CommonLib.sol";
import {AmmAdapterIdLib} from "../src/adapters/libs/AmmAdapterIdLib.sol";
import {DeployAdapterLib} from "../script/libs/DeployAdapterLib.sol";
import {Api3Adapter} from "../src/adapters/Api3Adapter.sol";
import {IBalancerGauge} from "../src/integrations/balancer/IBalancerGauge.sol";
import {StrategyIdLib} from "../src/strategies/libs/StrategyIdLib.sol";
import {BeetsStableFarm} from "../src/strategies/BeetsStableFarm.sol";
import {StrategyDeveloperLib} from "../src/strategies/libs/StrategyDeveloperLib.sol";
import {IGaugeEquivalent} from "../src/integrations/equalizer/IGaugeEquivalent.sol";
import {EqualizerFarmStrategy} from "../src/strategies/EqualizerFarmStrategy.sol";
import {BeetsWeightedFarm} from "../src/strategies/BeetsWeightedFarm.sol";

/// @dev Sonic network [chainId: 146] data library
//   _____             _
//  / ____|           (_)
// | (___   ___  _ __  _  ___
//  \___ \ / _ \| '_ \| |/ __|
//  ____) | (_) | | | | | (__
// |_____/ \___/|_| |_|_|\___|
//
/// @author Alien Deployer (https://github.com/a17)
library SonicLib {
    // initial addresses
    address public constant MULTISIG = 0xF564EBaC1182578398E94868bea1AbA6ba339652;

    // ERC20
    // https://docs.soniclabs.com/technology/contract-addresses
    address public constant TOKEN_wS = 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38;
    address public constant TOKEN_wETH = 0x50c42dEAcD8Fc9773493ED674b675bE577f2634b;
    address public constant TOKEN_USDC = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;
    address public constant TOKEN_stS = 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955;
    address public constant TOKEN_BEETS = 0x2D0E0814E62D80056181F5cd932274405966e4f0;
    address public constant TOKEN_EURC = 0xe715cbA7B5cCb33790ceBFF1436809d36cb17E57;
    address public constant TOKEN_EQUAL = 0xddF26B42C1d903De8962d3F79a74a501420d5F19;
    address public constant TOKEN_scUSD = 0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE;
    address public constant TOKEN_GOGLZ = 0x9fDbC3f8Abc05Fa8f3Ad3C17D2F806c1230c4564;

    // AMMs
    address public constant POOL_BEETS_wS_stS = 0x374641076B68371e69D03C417DAc3E5F236c32FA;
    address public constant POOL_BEETS_BEETS_stS = 0x10ac2F9DaE6539E77e372aDB14B1BF8fBD16b3e8;
    address public constant POOL_BEETS_wS_USDC = 0xE93a5fc4Ba77179F6843b30cff33a97d89FF441C;
    address public constant POOL_BEETS_USDC_scUSD = 0xCd4D2b142235D5650fFA6A38787eD0b7d7A51c0C;
    address public constant POOL_BEETS_scUSD_stS = 0x25ca5451CD5a50AB1d324B5E64F32C0799661891;
    address public constant POOL_SUSHI_wS_USDC = 0xE72b6DD415cDACeAC76616Df2C9278B33079E0D3;
    address public constant POOL_EQUALIZER_USDC_WETH = 0xbCbC5777537c0D0462fb82BA48Eeb6cb361E853f;
    address public constant POOL_EQUALIZER_wS_stS = 0xB75C9073ea00AbDa9ff420b5Ae46fEe248993380;
    address public constant POOL_EQUALIZER_wS_USDC = 0xdc85F86d5E3189e0d4a776e6Ae3B3911eC7B0133;
    address public constant POOL_EQUALIZER_wS_EQUAL = 0x139f8eCC5fC8Ef11226a83911FEBecC08476cfB1;
    address public constant POOL_EQUALIZER_USDC_scUSD = 0xB78CdF29F7E563ea447feBB5b48DDe9bC3278Ba4;
    address public constant POOL_EQUALIZER_wS_GOGLZ = 0x832e2bb9579f6fF038d3E704Fa1BB5B6B18a6521;

    // Beets
    address public constant BEETS_BALANCER_HELPERS = 0x8E9aa87E45e92bad84D5F8DD1bff34Fb92637dE9;
    address public constant BEETS_GAUGE_wS_stS = 0x8476F3A8DA52092e7835167AFe27835dC171C133;
    address public constant BEETS_GAUGE_USDC_scUSD = 0x33B29bcf17e866A35941e07CbAd54f1807B337f5;
    address public constant BEETS_GAUGE_scUSD_stS = 0xa472438718Fe7785107fCbE584d39183a6420D36;

    // Equalizer
    address public constant EQUALIZER_ROUTER_03 = 0xcC6169aA1E879d3a4227536671F85afdb2d23fAD;
    address public constant EQUALIZER_GAUGE_USDC_WETH = 0xf8F2462A8Fa08Df933C0d6bbaf34108Fd7af526E;
    address public constant EQUALIZER_GAUGE_wS_stS = 0x0DA2e6e170990dCDd046880fADC17ADF759B869e;
    address public constant EQUALIZER_GAUGE_wS_USDC = 0x9b55Fbd8Cd27B81aCc6adfd42D441858FeDe4326;
    address public constant EQUALIZER_GAUGE_USDC_scUSD = 0x8c030811a8C5E1890dAd1F5E581D28ac8740c532;
    address public constant EQUALIZER_GAUGE_wS_GOGLZ = 0x9E06a65E545b4Bd762158f6Bc34656DEe9693a4D;

    // Oracles
    address public constant ORACLE_API3_USDC_USD = 0xD3C586Eec1C6C3eC41D276a23944dea080eDCf7f;

    //noinspection NoReturn
    function platformDeployParams() internal pure returns (IPlatformDeployer.DeployPlatformParams memory p) {
        p.multisig = MULTISIG;
        p.version = "25.01.0-alpha";
        p.buildingPermitToken = address(0);
        p.buildingPayPerVaultToken = TOKEN_wS;
        p.networkName = "Sonic";
        p.networkExtra = CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0xfec160), bytes3(0x000000)));
        p.targetExchangeAsset = TOKEN_wS;
        p.gelatoAutomate = address(0);
        p.gelatoMinBalance = 1e16;
        p.gelatoDepositAmount = 2e16;
        p.fee = 30_000;
        p.feeShareVaultManager = 10_000;
        p.feeShareStrategyLogic = 40_000;
    }

    function deployAndSetupInfrastructure(address platform, bool showLog) internal {
        IFactory factory = IFactory(IPlatform(platform).factory());

        //region ----- Deployed Platform -----
        if (showLog) {
            console.log("Deployed Stability platform", IPlatform(platform).platformVersion());
            console.log("Platform address: ", platform);
        }
        //endregion ----- Deployed Platform -----

        //region ----- Deploy and setup vault types -----
        _addVaultType(factory, VaultTypeLib.COMPOUNDING, address(new CVault()), 10e6);
        //endregion ----- Deploy and setup vault types -----

        //region ----- Deploy and setup oracle adapters -----
        IPriceReader priceReader = PriceReader(IPlatform(platform).priceReader());
        // Api3
        {
            Proxy proxy = new Proxy();
            proxy.initProxy(address(new Api3Adapter()));
            Api3Adapter adapter = Api3Adapter(address(proxy));
            adapter.initialize(platform);
            address[] memory assets = new address[](1);
            assets[0] = TOKEN_USDC;
            address[] memory priceFeeds = new address[](1);
            priceFeeds[0] = ORACLE_API3_USDC_USD;
            adapter.addPriceFeeds(assets, priceFeeds);
            priceReader.addAdapter(address(adapter));
            LogDeployLib.logDeployAndSetupOracleAdapter("Api3", address(adapter), showLog);
        }
        //endregion ----- Deploy and setup oracle adapters -----

        //region ----- Deploy AMM adapters -----
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.UNISWAPV3);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE);
        IBalancerAdapter(
            IPlatform(platform).ammAdapter(keccak256(bytes(AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE))).proxy
        ).setupHelpers(BEETS_BALANCER_HELPERS);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.BALANCER_WEIGHTED);
        IBalancerAdapter(IPlatform(platform).ammAdapter(keccak256(bytes(AmmAdapterIdLib.BALANCER_WEIGHTED))).proxy)
            .setupHelpers(BEETS_BALANCER_HELPERS);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.SOLIDLY);
        LogDeployLib.logDeployAmmAdapters(platform, showLog);
        //endregion ----- Deploy AMM adapters -----

        //region ----- Setup Swapper -----
        {
            (ISwapper.AddPoolData[] memory bcPools, ISwapper.AddPoolData[] memory pools) = routes();
            ISwapper swapper = ISwapper(IPlatform(platform).swapper());
            swapper.addBlueChipsPools(bcPools, false);
            swapper.addPools(pools, false);
            address[] memory tokenIn = new address[](5);
            tokenIn[0] = TOKEN_wS;
            tokenIn[1] = TOKEN_stS;
            tokenIn[2] = TOKEN_BEETS;
            tokenIn[3] = TOKEN_EQUAL;
            tokenIn[4] = TOKEN_USDC;
            uint[] memory thresholdAmount = new uint[](5);
            thresholdAmount[0] = 1e12;
            thresholdAmount[1] = 1e16;
            thresholdAmount[2] = 1e10;
            thresholdAmount[3] = 1e12;
            thresholdAmount[4] = 1e4;
            swapper.setThresholds(tokenIn, thresholdAmount);
            LogDeployLib.logSetupSwapper(platform, showLog);
        }
        //endregion ----- Setup Swapper -----

        //region ----- Add farms -----
        factory.addFarms(farms());
        LogDeployLib.logAddedFarms(address(factory), showLog);
        //endregion ----- Add farms -----

        //region ----- Deploy strategy logics -----
        _addStrategyLogic(factory, StrategyIdLib.BEETS_STABLE_FARM, address(new BeetsStableFarm()), true);
        _addStrategyLogic(factory, StrategyIdLib.BEETS_WEIGHTED_FARM, address(new BeetsWeightedFarm()), true);
        _addStrategyLogic(factory, StrategyIdLib.EQUALIZER_FARM, address(new EqualizerFarmStrategy()), true);
        LogDeployLib.logDeployStrategies(platform, showLog);
        //endregion ----- Deploy strategy logics -----

        //region ----- Add DeX aggregators -----
        address[] memory dexAggRouter = new address[](1);
        dexAggRouter[0] = IPlatform(platform).swapper();
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
        bcPools[0] =
            _makePoolData(POOL_BEETS_wS_stS, AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE, TOKEN_stS, TOKEN_wS);
        // bcPools[1] = _makePoolData(POOL_BEETS_wS_USDC, AmmAdapterIdLib.BALANCER_WEIGHTED, TOKEN_USDC, TOKEN_wS);
        // bcPools[1] = _makePoolData(POOL_SUSHI_wS_USDC, AmmAdapterIdLib.UNISWAPV3, TOKEN_USDC, TOKEN_wS);
        bcPools[1] = _makePoolData(POOL_EQUALIZER_wS_USDC, AmmAdapterIdLib.SOLIDLY, TOKEN_USDC, TOKEN_wS);
        //endregion ----- BC pools ----

        //region ----- Pools ----
        pools = new ISwapper.AddPoolData[](8);
        uint i;
        pools[i++] =
            _makePoolData(POOL_BEETS_wS_stS, AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE, TOKEN_wS, TOKEN_stS);
        pools[i++] =
            _makePoolData(POOL_BEETS_wS_stS, AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE, TOKEN_stS, TOKEN_wS);
        pools[i++] = _makePoolData(POOL_BEETS_BEETS_stS, AmmAdapterIdLib.BALANCER_WEIGHTED, TOKEN_BEETS, TOKEN_stS);
        pools[i++] = _makePoolData(POOL_EQUALIZER_wS_USDC, AmmAdapterIdLib.SOLIDLY, TOKEN_USDC, TOKEN_wS);
        pools[i++] = _makePoolData(POOL_BEETS_USDC_scUSD, AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE, TOKEN_scUSD, TOKEN_USDC);
        pools[i++] = _makePoolData(POOL_EQUALIZER_wS_EQUAL, AmmAdapterIdLib.SOLIDLY, TOKEN_EQUAL, TOKEN_wS);
        pools[i++] = _makePoolData(POOL_EQUALIZER_USDC_WETH, AmmAdapterIdLib.SOLIDLY, TOKEN_wETH, TOKEN_USDC);
        pools[i++] = _makePoolData(POOL_EQUALIZER_wS_GOGLZ, AmmAdapterIdLib.SOLIDLY, TOKEN_GOGLZ, TOKEN_wS);
        //endregion ----- Pools ----
    }

    function farms() public view returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](8);
        uint i;

        _farms[i++] = _makeBeetsStableFarm(BEETS_GAUGE_wS_stS);
        _farms[i++] = _makeBeetsStableFarm(BEETS_GAUGE_USDC_scUSD);
        _farms[i++] = _makeEqualizerFarm(EQUALIZER_GAUGE_USDC_WETH);
        _farms[i++] = _makeEqualizerFarm(EQUALIZER_GAUGE_wS_stS);
        _farms[i++] = _makeEqualizerFarm(EQUALIZER_GAUGE_wS_USDC);
        _farms[i++] = _makeEqualizerFarm(EQUALIZER_GAUGE_USDC_scUSD);
        _farms[i++] = _makeBeetsWeightedFarm(BEETS_GAUGE_scUSD_stS);
        _farms[i++] = _makeEqualizerFarm(EQUALIZER_GAUGE_wS_GOGLZ);
    }

    function _makeBeetsStableFarm(address gauge) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IBalancerGauge(gauge).lp_token();
        farm.strategyLogicId = StrategyIdLib.BEETS_STABLE_FARM;
        uint len = IBalancerGauge(gauge).reward_count();
        farm.rewardAssets = new address[](len);
        for (uint i; i < len; ++i) {
          farm.rewardAssets[i] = IBalancerGauge(gauge).reward_tokens(i);
        }
        farm.addresses = new address[](1);
        farm.addresses[0] = gauge;
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeBeetsWeightedFarm(address gauge) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IBalancerGauge(gauge).lp_token();
        farm.strategyLogicId = StrategyIdLib.BEETS_WEIGHTED_FARM;
        uint len = IBalancerGauge(gauge).reward_count();
        farm.rewardAssets = new address[](len);
        for (uint i; i < len; ++i) {
            farm.rewardAssets[i] = IBalancerGauge(gauge).reward_tokens(i);
        }
        farm.addresses = new address[](1);
        farm.addresses[0] = gauge;
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeEqualizerFarm(address gauge) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IGaugeEquivalent(gauge).stake();
        farm.strategyLogicId = StrategyIdLib.EQUALIZER_FARM;
        uint len = IGaugeEquivalent(gauge).rewardsListLength();
        farm.rewardAssets = new address[](len);
        for (uint i; i < len; ++i) {
            farm.rewardAssets[i] = IGaugeEquivalent(gauge).rewardTokens(i);
        }
        farm.addresses = new address[](2);
        farm.addresses[0] = gauge;
        farm.addresses[1] = EQUALIZER_ROUTER_03;
        farm.nums = new uint[](0);
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
    }

    function _addVaultType(IFactory factory, string memory id, address implementation, uint buildingPrice) internal {
        factory.setVaultConfig(
            IFactory.VaultConfig({
                vaultType: id,
                implementation: implementation,
                deployAllowed: true,
                upgradeAllowed: true,
                buildingPrice: buildingPrice
            })
        );
    }

    function _addStrategyLogic(IFactory factory, string memory id, address implementation, bool farming) internal {
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: id,
                implementation: address(implementation),
                deployAllowed: true,
                upgradeAllowed: true,
                farming: farming,
                tokenId: type(uint).max
            }),
            StrategyDeveloperLib.getDeveloper(id)
        );
    }

    function testChainLib() external {}
}
