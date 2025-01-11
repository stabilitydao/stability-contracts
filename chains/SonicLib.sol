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
import {IGaugeV2_CL} from "../src/integrations/swapx/IGaugeV2_CL.sol";
import {IGaugeV2} from "../src/integrations/swapx/IGaugeV2.sol";
import {IICHIVault} from "../src/integrations/ichi/IICHIVault.sol";
import {IchiSwapXFarmStrategy} from "../src/strategies/IchiSwapXFarmStrategy.sol";
import {SwapXFarmStrategy} from "../src/strategies/SwapXFarmStrategy.sol";

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
    address public constant TOKEN_SACRA = 0x7AD5935EA295c4E743e4f2f5B4CDA951f41223c2;
    address public constant TOKEN_SACRA_GEM_1 = 0xfC0dd337b92Baa949bC5D25FD9A99Cb3b6873204;
    address public constant TOKEN_SWPx = 0xA04BC7140c26fc9BB1F36B1A604C7A5a88fb0E70;
    address public constant TOKEN_scETH = 0x3bcE5CB273F0F148010BbEa2470e7b5df84C7812;
    address public constant TOKEN_atETH = 0x284D81e48fBc782Aa9186a03a226690aEA5cBe0E;
    address public constant TOKEN_AUR = 0x7F144F8691CbA3d2EfD8e5bcf042f9303EE31a46;
    address public constant TOKEN_auUSDC = 0xd6a69EBFa44f78cEe454A2Df2C77751A42f8f38c;
    address public constant TOKEN_NAVI = 0x6881B80ea7C858E4aEEf63893e18a8A36f3682f3;
    address public constant TOKEN_ECO = 0x7A08Bf5304094CA4C7b4132Ef62b5EDc4a3478B7;
    address public constant TOKEN_INDI = 0x4EEC869d847A6d13b0F6D1733C5DEC0d1E741B4f;
    address public constant TOKEN_BRUSH = 0xE51EE9868C1f0d6cd968A8B8C8376Dc2991BFE44;
    address public constant TOKEN_TYSG = 0x56192E94434c4fd3278b4Fa53039293fB00DE3DB;

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
    address public constant POOL_EQUALIZER_wS_NAVI = 0x25f21F51b3D6322E165b80C9fdE31104CB82df04;
    address public constant POOL_EQUALIZER_wS_ECO = 0x93B3Db87d07e4925274174CbD650EFdcd8885Cc6;
    address public constant POOL_EQUALIZER_ECO_EQUAL = 0x88615ba8aa369f2f27E4a6e8f66fdE85F1Ce15ec;
    address public constant POOL_EQUALIZER_wS_INDI = 0x913B1c9924F563692b3A306C90C9fDe9f825Ca27;
    address public constant POOL_EQUALIZER_wS_BRUSH = 0x38cFA6cB37d074B6E954C52d10a4cf0e4268607b;
    address public constant POOL_SWAPX_CL_wS_SACRA = 0x875819746112630cEe95aA78E4327cd4837Da70D;
    address public constant POOL_SWAPX_CL_wS_SWPx = 0xbeca246A76942502f61bFe88F60bbc87DaFefe80;
    address public constant POOL_SWAPX_CL_USDC_SWPx = 0x467865E7Ce29E7ED8f362D51Fd7141117B234b44;
    address public constant POOL_SWAPX_CL_wS_stS = 0xD760791B29e7894FB827A94Ca433254bb5aFB653;
    address public constant POOL_SWAPX_CL_wS_USDC = 0x5C4B7d607aAF7B5CDE9F09b5F03Cf3b5c923AEEa;
    address public constant POOL_SWAPX_CL_USDC_WETH = 0xeC4Ee7d6988Ab06F7a8DAaf8C5FDfFdE6321Be68;
    address public constant POOL_SWAPX_CL_USDC_scUSD = 0xDd35c88B1754879EF86BBF3A24F81fCCA5Eb6B5D;
    address public constant POOL_SWAPX_CL_wS_scETH = 0xFC64BD7c84F7Dc1387D6E752679a533F22f6F1DB;
    address public constant POOL_SWAPX_CL_USDC_stS = 0x5DDbeF774488cc68266d5F15bFB08eaA7cd513F9;
    address public constant POOL_SWAPX_CL_atETH_scETH = 0xCe39D66872015a8d1B2070725E6BFc687A418bD0;
    address public constant POOL_SWAPX_CL_wS_SACRA_GEM_1 = 0x5e1Cb0d1196FF3451204fC40415A81a4d24Ec7eD;
    address public constant POOL_SWAPX_USDC_scUSD = 0xBb8aE5b889243561ac9261F22F592B72250AFd1F;
    address public constant POOL_SWAPX_wS_GOGLZ = 0xE6aA7CA47DDb6203e71d4D1497959Da51F87AA98;
    address public constant POOL_SWAPX_AUR_auUSDC = 0xf9b7a6Da525f6f05910f99b298bb792025128C6f;
    address public constant POOL_SWAPX_USDC_AUR = 0xE87080413295b7a3B9c63F82a3337a882750F974;
    address public constant POOL_SWAPX_wS_TYSG = 0x24f5cd888057A721F1ACD7CBA1Afa7A8384c3e12;

    // ALMs
    address public constant ALM_ICHI_SWAPX_SACRA_wS = 0x13939Ac0f09dADe88F8b1d86C26daD934d973081;
    address public constant ALM_ICHI_SWAPX_wS_SACRA = 0x32D1E0647fD2AE199bB0599Fe62A95e522C11bf3;
    address public constant ALM_ICHI_SWAPX_stS_wS = 0xa68D5DbAe00960De66DdEaD4d53faea39f21983b;
    address public constant ALM_ICHI_SWAPX_wS_stS = 0xfD10ac67449C16F368a4BB49f544E0A865A77614;
    address public constant ALM_ICHI_SWAPX_SACRA_GEM_1_wS = 0x515626bC050c6fc1B000be7F4FDa71422CaD3e09;
    address public constant ALM_ICHI_SWAPX_wS_SACRA_GEM_1 = 0xB97908b0Bec1Fac52281d108a56B055B633FDf67;
    address public constant ALM_ICHI_SWAPX_wS_USDC = 0x5F62d612c69fF7BE3FBd9a0cD530D57bCbC7b642;
    address public constant ALM_ICHI_SWAPX_USDC_wS = 0xc263e421Df94bdf57B27120A9B7B8534A6901D95;
    address public constant ALM_ICHI_SWAPX_scUSD_USDC = 0x776C31466F19D4e2c71bCE16c0549a8Bc0E37e17;
    address public constant ALM_ICHI_SWAPX_USDC_scUSD = 0xF77CeeD15596BfC127D17bA45dEA9767BC349Be0;

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
    address public constant EQUALIZER_GAUGE_wS_NAVI = 0xe33588B5507E7c1D8Dd8367Cd8C7CE406DAeb019;
    address public constant EQUALIZER_GAUGE_wS_ECO = 0xE9DB22DC69129FD131CB744e8E638A8FA084e66e;
    address public constant EQUALIZER_GAUGE_ECO_EQUAL = 0xDAC4c0fcd65C71070E1b14f1deA8Ce48E746B2fD;
    address public constant EQUALIZER_GAUGE_wS_INDI = 0x15c2B42F6001758edDd9Cd13f327cdc812E5795D;
    address public constant EQUALIZER_GAUGE_wS_BRUSH = 0xA4Df0a210a5E242BE68E8a2b780ecc854ADD3583;

    // SwapX
    address public constant SWAPX_ROUTER_V2 = 0xF5F7231073b3B41c04BA655e1a7438b1a7b29c27;
    address public constant SWAPX_GAUGE_ICHI_SACRA_wS = 0x413610103721Df45C7E8333D5E34Bb39975762f3;
    address public constant SWAPX_GAUGE_ICHI_wS_SACRA = 0x2a2EF9F07c998140eA3709826e28157971F85d30;
    address public constant SWAPX_GAUGE_ICHI_stS_wS = 0x2f9e2852de03c42c13d3dCdD2C57c0b3cF0382c1;
    address public constant SWAPX_GAUGE_ICHI_wS_stS = 0xC693c6fc1d2b44DfB5C5aa05Ca2b02A91DB97528;
    address public constant SWAPX_GAUGE_ICHI_SACRA_GEM_1_wS = 0xF46AeD788930E6Dd7f5881b9aeDf692dD6552d58;
    address public constant SWAPX_GAUGE_ICHI_wS_SACRA_GEM_1 = 0xCe9f06c3d88fe91F16A8fb5489860677a2358d6F;
    address public constant SWAPX_GAUGE_ICHI_wS_USDC = 0xdcE26623440B34a93e748e131577049a8d84DdEd;
    address public constant SWAPX_GAUGE_ICHI_USDC_wS = 0x29d10053BE597E0eBe6BD0434c4f4b750F0f3b69;
    address public constant SWAPX_GAUGE_ICHI_scUSD_USDC = 0x4604782BcD6F749B271Fc9d14BFd583be6e5a6cf;
    address public constant SWAPX_GAUGE_ICHI_USDC_scUSD = 0x640429B0633851F487639BcDd8Ed523DDf1Bbff8;
    address public constant SWAPX_GAUGE_USDC_scUSD = 0x2036D05eCA7fe86cD224927883490A255EF552BA;
    address public constant SWAPX_GAUGE_wS_GOGLZ = 0x5D671DE88045626e50Be05C1D438b2B9908cFa97;
    address public constant SWAPX_GAUGE_AUR_auUSDC = 0xca958280Ba083545C36A64e1AED18075317E3529;
    address public constant SWAPX_GAUGE_wS_TYSG = 0xB7B6fC72CbC8E8FA67737f83e945Db2795a66Ef7;

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
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.ALGEBRA_V4);
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
        _addStrategyLogic(factory, StrategyIdLib.ICHI_SWAPX_FARM, address(new IchiSwapXFarmStrategy()), true);
        _addStrategyLogic(factory, StrategyIdLib.SWAPX_FARM, address(new SwapXFarmStrategy()), true);
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
        bcPools[0] = _makePoolData(POOL_BEETS_wS_stS, AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE, TOKEN_stS, TOKEN_wS);
        // bcPools[1] = _makePoolData(POOL_BEETS_wS_USDC, AmmAdapterIdLib.BALANCER_WEIGHTED, TOKEN_USDC, TOKEN_wS);
        // bcPools[1] = _makePoolData(POOL_SUSHI_wS_USDC, AmmAdapterIdLib.UNISWAPV3, TOKEN_USDC, TOKEN_wS);
        bcPools[1] = _makePoolData(POOL_EQUALIZER_wS_USDC, AmmAdapterIdLib.SOLIDLY, TOKEN_USDC, TOKEN_wS);
        //endregion ----- BC pools ----

        //region ----- Pools ----
        pools = new ISwapper.AddPoolData[](13);
        uint i;
        pools[i++] = _makePoolData(POOL_BEETS_wS_stS, AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE, TOKEN_wS, TOKEN_stS);
        pools[i++] = _makePoolData(POOL_BEETS_wS_stS, AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE, TOKEN_stS, TOKEN_wS);
        pools[i++] = _makePoolData(POOL_BEETS_BEETS_stS, AmmAdapterIdLib.BALANCER_WEIGHTED, TOKEN_BEETS, TOKEN_stS);
        pools[i++] = _makePoolData(POOL_EQUALIZER_wS_USDC, AmmAdapterIdLib.SOLIDLY, TOKEN_USDC, TOKEN_wS);
        pools[i++] =
            _makePoolData(POOL_BEETS_USDC_scUSD, AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE, TOKEN_scUSD, TOKEN_USDC);
        pools[i++] = _makePoolData(POOL_EQUALIZER_wS_EQUAL, AmmAdapterIdLib.SOLIDLY, TOKEN_EQUAL, TOKEN_wS);
        pools[i++] = _makePoolData(POOL_EQUALIZER_USDC_WETH, AmmAdapterIdLib.SOLIDLY, TOKEN_wETH, TOKEN_USDC);
        pools[i++] = _makePoolData(POOL_EQUALIZER_wS_GOGLZ, AmmAdapterIdLib.SOLIDLY, TOKEN_GOGLZ, TOKEN_wS);
        pools[i++] = _makePoolData(POOL_SWAPX_CL_wS_SWPx, AmmAdapterIdLib.ALGEBRA_V4, TOKEN_SWPx, TOKEN_wS);
        pools[i++] = _makePoolData(POOL_SWAPX_CL_wS_SACRA, AmmAdapterIdLib.ALGEBRA_V4, TOKEN_SACRA, TOKEN_wS);
        pools[i++] =
            _makePoolData(POOL_SWAPX_CL_wS_SACRA_GEM_1, AmmAdapterIdLib.ALGEBRA_V4, TOKEN_SACRA_GEM_1, TOKEN_wS);
        pools[i++] = _makePoolData(POOL_SWAPX_USDC_AUR, AmmAdapterIdLib.SOLIDLY, TOKEN_AUR, TOKEN_USDC);
        pools[i++] = _makePoolData(POOL_SWAPX_AUR_auUSDC, AmmAdapterIdLib.SOLIDLY, TOKEN_auUSDC, TOKEN_AUR);
        //endregion ----- Pools ----
    }

    function farms() public view returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](17);
        uint i;

        _farms[i++] = _makeBeetsStableFarm(BEETS_GAUGE_wS_stS);
        _farms[i++] = _makeBeetsStableFarm(BEETS_GAUGE_USDC_scUSD);
        _farms[i++] = _makeEqualizerFarm(EQUALIZER_GAUGE_USDC_WETH);
        _farms[i++] = _makeEqualizerFarm(EQUALIZER_GAUGE_wS_stS);
        _farms[i++] = _makeEqualizerFarm(EQUALIZER_GAUGE_wS_USDC);
        _farms[i++] = _makeEqualizerFarm(EQUALIZER_GAUGE_USDC_scUSD);
        _farms[i++] = _makeBeetsWeightedFarm(BEETS_GAUGE_scUSD_stS);
        _farms[i++] = _makeEqualizerFarm(EQUALIZER_GAUGE_wS_GOGLZ);
        _farms[i++] = _makeIchiSwapXFarm(SWAPX_GAUGE_ICHI_SACRA_wS);
        _farms[i++] = _makeIchiSwapXFarm(SWAPX_GAUGE_ICHI_wS_SACRA);
        _farms[i++] = _makeIchiSwapXFarm(SWAPX_GAUGE_ICHI_stS_wS);
        _farms[i++] = _makeIchiSwapXFarm(SWAPX_GAUGE_ICHI_wS_stS);
        _farms[i++] = _makeIchiSwapXFarm(SWAPX_GAUGE_ICHI_SACRA_GEM_1_wS);
        _farms[i++] = _makeIchiSwapXFarm(SWAPX_GAUGE_ICHI_wS_SACRA_GEM_1);
        _farms[i++] = _makeSwapXFarm(SWAPX_GAUGE_USDC_scUSD);
        _farms[i++] = _makeSwapXFarm(SWAPX_GAUGE_wS_GOGLZ);
        _farms[i++] = _makeSwapXFarm(SWAPX_GAUGE_AUR_auUSDC);
    }

    function _makeSwapXFarm(address gauge) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IGaugeV2(gauge).TOKEN();
        farm.strategyLogicId = StrategyIdLib.SWAPX_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = IGaugeV2(gauge).rewardToken();
        farm.addresses = new address[](2);
        farm.addresses[0] = gauge;
        farm.addresses[1] = SWAPX_ROUTER_V2;
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeIchiSwapXFarm(address gauge) internal view returns (IFactory.Farm memory) {
        address alm = IGaugeV2_CL(gauge).TOKEN();
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IICHIVault(alm).pool();
        farm.strategyLogicId = StrategyIdLib.ICHI_SWAPX_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = IGaugeV2_CL(gauge).rewardToken();
        farm.addresses = new address[](2);
        farm.addresses[0] = alm;
        farm.addresses[1] = gauge;
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
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
