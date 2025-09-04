// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ChainlinkMinimal2V3Adapter} from "../../src/adapters/ChainlinkMinimal2V3Adapter.sol";
import {ALMLib} from "../../src/strategies/libs/ALMLib.sol";
import {ALMPositionNameLib} from "../../src/strategies/libs/ALMPositionNameLib.sol";
import {ALMShadowFarmStrategy} from "../../src/strategies/ALMShadowFarmStrategy.sol";
import {AaveMerklFarmStrategy} from "../../src/strategies/AaveMerklFarmStrategy.sol";
import {AaveStrategy} from "../../src/strategies/AaveStrategy.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {Api3Adapter} from "../../src/adapters/Api3Adapter.sol";
import {BeetsStableFarm} from "../../src/strategies/BeetsStableFarm.sol";
import {BeetsWeightedFarm} from "../../src/strategies/BeetsWeightedFarm.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {ChainlinkAdapter} from "../../src/adapters/ChainlinkAdapter.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";
import {DeployAdapterLib} from "../../script/libs/DeployAdapterLib.sol";
import {EqualizerFarmStrategy} from "../../src/strategies/EqualizerFarmStrategy.sol";
import {EulerStrategy} from "../../src/strategies/EulerStrategy.sol";
import {GammaEqualizerFarmStrategy} from "../../src/strategies/GammaEqualizerFarmStrategy.sol";
import {GammaUniswapV3MerklFarmStrategy} from "../../src/strategies/GammaUniswapV3MerklFarmStrategy.sol";
import {IBalancerAdapter} from "../../src/interfaces/IBalancerAdapter.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IPlatformDeployer} from "../../src/interfaces/IPlatformDeployer.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {IchiEqualizerFarmStrategy} from "../../src/strategies/IchiEqualizerFarmStrategy.sol";
import {IchiSwapXFarmStrategy} from "../../src/strategies/IchiSwapXFarmStrategy.sol";
import {LogDeployLib, console} from "../../script/libs/LogDeployLib.sol";
import {PriceReader} from "../../src/core/PriceReader.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SiloALMFStrategy} from "../../src/strategies/SiloALMFStrategy.sol";
import {SiloAdvancedLeverageStrategy} from "../../src/strategies/SiloAdvancedLeverageStrategy.sol";
import {SiloFarmStrategy} from "../../src/strategies/SiloFarmStrategy.sol";
import {SiloLeverageStrategy} from "../../src/strategies/SiloLeverageStrategy.sol";
import {SiloManagedFarmStrategy} from "../../src/strategies/SiloManagedFarmStrategy.sol";
import {SiloStrategy} from "../../src/strategies/SiloStrategy.sol";
import {SonicConstantsLib} from "./SonicConstantsLib.sol";
import {SonicFarmMakerLib} from "./SonicFarmMakerLib.sol";
import {StrategyDeveloperLib} from "../../src/strategies/libs/StrategyDeveloperLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {SwapXFarmStrategy} from "../../src/strategies/SwapXFarmStrategy.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {CompoundV2Strategy} from "../../src/strategies/CompoundV2Strategy.sol";
import {EulerMerklFarmStrategy} from "../../src/strategies/EulerMerklFarmStrategy.sol";

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
    //noinspection NoReturn
    function platformDeployParams() internal pure returns (IPlatformDeployer.DeployPlatformParams memory p) {
        p.multisig = SonicConstantsLib.MULTISIG;
        p.version = "25.01.0-alpha";
        p.buildingPermitToken = address(0);
        p.buildingPayPerVaultToken = SonicConstantsLib.TOKEN_wS;
        p.networkName = "Sonic";
        p.networkExtra = CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0xfec160), bytes3(0x000000)));
        p.targetExchangeAsset = SonicConstantsLib.TOKEN_wS;
        p.fee = 30_000;
    }

    function deployAndSetupInfrastructure(address platform, bool showLog) internal {
        IFactory factory = IFactory(IPlatform(platform).factory());

        //region ----- Deployed Platform -----
        if (showLog) {
            console.log("Deployed Stability platform", IPlatform(platform).platformVersion());
            console.log("Platform address: ", platform);
        }
        //endregion

        //region ----- Deploy and setup vault types -----
        _addVaultType(factory, VaultTypeLib.COMPOUNDING, address(new CVault()), 10e6);
        //endregion

        //region ----- Deploy and setup oracle adapters -----
        IPriceReader priceReader = PriceReader(IPlatform(platform).priceReader());
        // Api3
        {
            Proxy proxy = new Proxy();
            proxy.initProxy(address(new Api3Adapter()));
            Api3Adapter adapter = Api3Adapter(address(proxy));
            adapter.initialize(platform);
            address[] memory assets = new address[](1);
            assets[0] = SonicConstantsLib.TOKEN_USDC;
            address[] memory priceFeeds = new address[](1);
            priceFeeds[0] = SonicConstantsLib.ORACLE_API3_USDC_USD;
            adapter.addPriceFeeds(assets, priceFeeds);
            priceReader.addAdapter(address(adapter));
            LogDeployLib.logDeployAndSetupOracleAdapter("Api3", address(adapter), showLog);
        }
        // Chainlink
        {
            Proxy proxy = new Proxy();
            proxy.initProxy(address(new ChainlinkAdapter()));
            ChainlinkAdapter adapter = ChainlinkAdapter(address(proxy));
            adapter.initialize(platform);
            address[] memory assets = new address[](4);
            assets[0] = SonicConstantsLib.TOKEN_scUSD;
            assets[1] = SonicConstantsLib.TOKEN_wS;
            assets[2] = SonicConstantsLib.WRAPPED_METAVAULT_metaUSD;
            assets[3] = SonicConstantsLib.WRAPPED_METAVAULT_metaS;
            address[] memory priceFeeds = new address[](4);
            priceFeeds[0] = SonicConstantsLib.ORACLE_CHAINLINK_scUSD;
            priceFeeds[1] = SonicConstantsLib.ORACLE_CHAINLINK_wS;
            priceFeeds[2] = address(new ChainlinkMinimal2V3Adapter(SonicConstantsLib.ORACLE_CHAINLINK_metaUSD));
            priceFeeds[3] = address(new ChainlinkMinimal2V3Adapter(SonicConstantsLib.ORACLE_CHAINLINK_metaS));
            adapter.addPriceFeeds(assets, priceFeeds);
            priceReader.addAdapter(address(adapter));
            LogDeployLib.logDeployAndSetupOracleAdapter("Chainlink", address(adapter), showLog);
        }
        //endregion

        //region ----- Deploy AMM adapters -----
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.UNISWAPV3);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE);
        IBalancerAdapter(
            IPlatform(platform).ammAdapter(keccak256(bytes(AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE))).proxy
        ).setupHelpers(SonicConstantsLib.BEETS_BALANCER_HELPERS);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.BALANCER_WEIGHTED);
        IBalancerAdapter(IPlatform(platform).ammAdapter(keccak256(bytes(AmmAdapterIdLib.BALANCER_WEIGHTED))).proxy)
            .setupHelpers(SonicConstantsLib.BEETS_BALANCER_HELPERS);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.SOLIDLY);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.ALGEBRA_V4);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.ERC_4626);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.BALANCER_V3_STABLE);
        IBalancerAdapter(IPlatform(platform).ammAdapter(keccak256(bytes(AmmAdapterIdLib.BALANCER_V3_STABLE))).proxy)
            .setupHelpers(SonicConstantsLib.BEETS_V3_ROUTER);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.PENDLE);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.META_VAULT);
        LogDeployLib.logDeployAmmAdapters(platform, showLog);
        //endregion

        //region ----- Setup Swapper -----
        {
            (ISwapper.AddPoolData[] memory bcPools, ISwapper.AddPoolData[] memory pools) = routes();
            ISwapper swapper = ISwapper(IPlatform(platform).swapper());
            swapper.addBlueChipsPools(bcPools, false);
            swapper.addPools(pools, false);
            address[] memory tokenIn = new address[](7);
            tokenIn[0] = SonicConstantsLib.TOKEN_wS;
            tokenIn[1] = SonicConstantsLib.TOKEN_stS;
            tokenIn[2] = SonicConstantsLib.TOKEN_BEETS;
            tokenIn[3] = SonicConstantsLib.TOKEN_EQUAL;
            tokenIn[4] = SonicConstantsLib.TOKEN_USDC;
            tokenIn[5] = SonicConstantsLib.TOKEN_DIAMONDS;
            tokenIn[6] = SonicConstantsLib.TOKEN_USDT;
            uint[] memory thresholdAmount = new uint[](7);
            thresholdAmount[0] = 1e12;
            thresholdAmount[1] = 1e16;
            thresholdAmount[2] = 1e10;
            thresholdAmount[3] = 1e12;
            thresholdAmount[4] = 1e4;
            thresholdAmount[5] = 1e15;
            thresholdAmount[6] = 1e4;
            swapper.setThresholds(tokenIn, thresholdAmount);
            LogDeployLib.logSetupSwapper(platform, showLog);
        }
        //endregion

        //region ----- Add farms -----
        factory.addFarms(farms());
        LogDeployLib.logAddedFarms(address(factory), showLog);
        //endregion

        //region ----- Add strategy available init params -----
        IFactory.StrategyAvailableInitParams memory p;
        p.initAddresses = new address[](4);
        p.initAddresses[0] = SonicConstantsLib.SILO_VAULT_3_stS;
        p.initAddresses[1] = SonicConstantsLib.SILO_VAULT_3_wS;
        p.initAddresses[2] = SonicConstantsLib.BEETS_VAULT;
        p.initAddresses[3] = SonicConstantsLib.SILO_LENS;
        p.initNums = new uint[](1);
        p.initNums[0] = 1;
        p.initTicks = new int24[](0);
        factory.setStrategyAvailableInitParams(StrategyIdLib.SILO_LEVERAGE, p);
        p.initAddresses = new address[](4);
        p.initAddresses[0] = SonicConstantsLib.SILO_VAULT_23_wstkscUSD;
        p.initAddresses[1] = SonicConstantsLib.SILO_VAULT_23_USDC;
        p.initAddresses[2] = SonicConstantsLib.BEETS_VAULT;
        p.initAddresses[3] = SonicConstantsLib.SILO_LENS;
        p.initNums = new uint[](1);
        p.initNums[0] = 87_00;
        p.initTicks = new int24[](0);
        factory.setStrategyAvailableInitParams(StrategyIdLib.SILO_ADVANCED_LEVERAGE, p);
        p.initAddresses = new address[](4);
        p.initAddresses[0] = SonicConstantsLib.SILO_VAULT_8_USDC;
        p.initAddresses[1] = SonicConstantsLib.SILO_VAULT_27_USDC;
        p.initAddresses[2] = SonicConstantsLib.SILO_VAULT_51_wS;
        p.initAddresses[3] = SonicConstantsLib.SILO_VAULT_31_WBTC;
        factory.setStrategyAvailableInitParams(StrategyIdLib.SILO, p);
        p.initAddresses = new address[](1);
        p.initAddresses[0] = SonicConstantsLib.EULER_VAULT_wS_Re7;
        p.initNums = new uint[](0);
        p.initTicks = new int24[](0);
        factory.setStrategyAvailableInitParams(StrategyIdLib.EULER, p);
        p.initAddresses = new address[](7);
        p.initAddresses[0] = SonicConstantsLib.STABILITY_SONIC_wS;
        p.initAddresses[1] = SonicConstantsLib.STABILITY_SONIC_USDC;
        p.initAddresses[2] = SonicConstantsLib.STABILITY_SONIC_scUSD;
        p.initAddresses[3] = SonicConstantsLib.STABILITY_SONIC_WETH;
        p.initAddresses[4] = SonicConstantsLib.STABILITY_SONIC_USDT;
        p.initAddresses[5] = SonicConstantsLib.STABILITY_SONIC_wOS;
        p.initAddresses[6] = SonicConstantsLib.STABILITY_SONIC_stS;
        p.initNums = new uint[](0);
        p.initTicks = new int24[](0);
        factory.setStrategyAvailableInitParams(StrategyIdLib.AAVE, p);

        p.initAddresses = new address[](3);
        p.initAddresses[0] = SonicConstantsLib.ENCLABS_VTOKEN_CORE_USDC;
        p.initAddresses[1] = SonicConstantsLib.ENCLABS_VTOKEN_CORE_wS;
        p.initAddresses[2] = SonicConstantsLib.ENCLABS_VTOKEN_wmetaUSD;
        p.initNums = new uint[](0);
        p.initTicks = new int24[](0);
        factory.setStrategyAvailableInitParams(StrategyIdLib.COMPOUND_V2, p);

        //endregion -- Add strategy available init params -----

        //region ----- Deploy strategy logics -----
        _addStrategyLogic(factory, StrategyIdLib.BEETS_STABLE_FARM, address(new BeetsStableFarm()), true);
        _addStrategyLogic(factory, StrategyIdLib.BEETS_WEIGHTED_FARM, address(new BeetsWeightedFarm()), true);
        _addStrategyLogic(factory, StrategyIdLib.EQUALIZER_FARM, address(new EqualizerFarmStrategy()), true);
        _addStrategyLogic(factory, StrategyIdLib.ICHI_SWAPX_FARM, address(new IchiSwapXFarmStrategy()), true);
        _addStrategyLogic(factory, StrategyIdLib.SWAPX_FARM, address(new SwapXFarmStrategy()), true);
        _addStrategyLogic(
            factory, StrategyIdLib.GAMMA_UNISWAPV3_MERKL_FARM, address(new GammaUniswapV3MerklFarmStrategy()), true
        );
        _addStrategyLogic(factory, StrategyIdLib.SILO_FARM, address(new SiloFarmStrategy()), true);
        _addStrategyLogic(factory, StrategyIdLib.ALM_SHADOW_FARM, address(new ALMShadowFarmStrategy()), true);
        _addStrategyLogic(factory, StrategyIdLib.SILO_LEVERAGE, address(new SiloLeverageStrategy()), false);
        _addStrategyLogic(
            factory, StrategyIdLib.SILO_ADVANCED_LEVERAGE, address(new SiloAdvancedLeverageStrategy()), false
        );
        _addStrategyLogic(factory, StrategyIdLib.GAMMA_EQUALIZER_FARM, address(new GammaEqualizerFarmStrategy()), true);
        _addStrategyLogic(factory, StrategyIdLib.ICHI_EQUALIZER_FARM, address(new IchiEqualizerFarmStrategy()), true);
        _addStrategyLogic(factory, StrategyIdLib.EULER_MERKL_FARM, address(new EulerMerklFarmStrategy()), true);
        _addStrategyLogic(factory, StrategyIdLib.SILO, address(new SiloStrategy()), false);
        _addStrategyLogic(factory, StrategyIdLib.EULER, address(new EulerStrategy()), false);
        _addStrategyLogic(factory, StrategyIdLib.AAVE, address(new AaveStrategy()), false);
        _addStrategyLogic(factory, StrategyIdLib.SILO_MANAGED_FARM, address(new SiloManagedFarmStrategy()), true);
        _addStrategyLogic(factory, StrategyIdLib.SILO_ALMF_FARM, address(new SiloALMFStrategy()), true);
        _addStrategyLogic(factory, StrategyIdLib.AAVE_MERKL_FARM, address(new AaveMerklFarmStrategy()), true);
        _addStrategyLogic(factory, StrategyIdLib.COMPOUND_V2, address(new CompoundV2Strategy()), false);
        LogDeployLib.logDeployStrategies(platform, showLog);
        //endregion

        //region ----- Add DeX aggregators -----
        address[] memory dexAggRouter = new address[](1);
        dexAggRouter[0] = IPlatform(platform).swapper();
        IPlatform(platform).addDexAggregators(dexAggRouter);
        //endregion
    }

    function routes()
        public
        pure
        returns (ISwapper.AddPoolData[] memory bcPools, ISwapper.AddPoolData[] memory pools)
    {
        //region ----- BC pools ----
        bcPools = new ISwapper.AddPoolData[](2);
        bcPools[0] = _makePoolData(SonicConstantsLib.POOL_SWAPX_CL_wS_stS, AmmAdapterIdLib.ALGEBRA_V4, SonicConstantsLib.TOKEN_stS, SonicConstantsLib.TOKEN_wS);
        bcPools[1] = _makePoolData(SonicConstantsLib.POOL_SUSHI_wS_USDC, AmmAdapterIdLib.UNISWAPV3, SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_wS);
        //endregion ----- BC pools ----

        //region ----- Pools ----
        pools = new ISwapper.AddPoolData[](46);

        uint i;
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_SHADOW_CL_USDC_USDT, AmmAdapterIdLib.UNISWAPV3, SonicConstantsLib.TOKEN_USDT, SonicConstantsLib.TOKEN_USDC);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_SWAPX_CL_wS_stS, AmmAdapterIdLib.ALGEBRA_V4, SonicConstantsLib.TOKEN_wS, SonicConstantsLib.TOKEN_stS);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_SWAPX_CL_wS_stS, AmmAdapterIdLib.ALGEBRA_V4, SonicConstantsLib.TOKEN_stS, SonicConstantsLib.TOKEN_wS);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_BEETS_BEETS_stS, AmmAdapterIdLib.BALANCER_WEIGHTED, SonicConstantsLib.TOKEN_BEETS, SonicConstantsLib.TOKEN_stS);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_SUSHI_wS_USDC, AmmAdapterIdLib.UNISWAPV3, SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.TOKEN_wS);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_SHADOW_CL_USDC_scUSD_100, AmmAdapterIdLib.UNISWAPV3, SonicConstantsLib.TOKEN_scUSD, SonicConstantsLib.TOKEN_USDC);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_EQUALIZER_wS_EQUAL, AmmAdapterIdLib.SOLIDLY, SonicConstantsLib.TOKEN_EQUAL, SonicConstantsLib.TOKEN_wS);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_SWAPX_CL_USDC_WETH, AmmAdapterIdLib.ALGEBRA_V4, SonicConstantsLib.TOKEN_wETH, SonicConstantsLib.TOKEN_USDC);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_EQUALIZER_wS_GOGLZ, AmmAdapterIdLib.SOLIDLY, SonicConstantsLib.TOKEN_GOGLZ, SonicConstantsLib.TOKEN_wS);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_SWAPX_CL_wS_SWPx, AmmAdapterIdLib.ALGEBRA_V4, SonicConstantsLib.TOKEN_SWPx, SonicConstantsLib.TOKEN_wS);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_SWAPX_CL_wS_SACRA, AmmAdapterIdLib.ALGEBRA_V4, SonicConstantsLib.TOKEN_SACRA, SonicConstantsLib.TOKEN_wS);
        pools[i++] =
            _makePoolData(SonicConstantsLib.POOL_SWAPX_CL_wS_SACRA_GEM_1, AmmAdapterIdLib.ALGEBRA_V4, SonicConstantsLib.TOKEN_SACRA_GEM_1, SonicConstantsLib.TOKEN_wS);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_SWAPX_USDC_AUR, AmmAdapterIdLib.SOLIDLY, SonicConstantsLib.TOKEN_AUR, SonicConstantsLib.TOKEN_USDC);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_SWAPX_AUR_auUSDC, AmmAdapterIdLib.SOLIDLY, SonicConstantsLib.TOKEN_auUSDC, SonicConstantsLib.TOKEN_AUR);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_SHADOW_wS_SHADOW, AmmAdapterIdLib.SOLIDLY, SonicConstantsLib.TOKEN_SHADOW, SonicConstantsLib.TOKEN_wS);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_SHADOW_CL_wS_BRUSH_5000, AmmAdapterIdLib.UNISWAPV3, SonicConstantsLib.TOKEN_BRUSH, SonicConstantsLib.TOKEN_wS);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_SHADOW_CL_scETH_WETH_100, AmmAdapterIdLib.UNISWAPV3, SonicConstantsLib.TOKEN_scETH, SonicConstantsLib.TOKEN_wETH);

        pools[i++] =
            _makePoolData(SonicConstantsLib.POOL_SWAPX_CL_wstkscUSD_scUSD, AmmAdapterIdLib.ALGEBRA_V4, SonicConstantsLib.TOKEN_wstkscUSD, SonicConstantsLib.TOKEN_scUSD);
        pools[i++] = _makePoolData(SonicConstantsLib.TOKEN_wstkscUSD, AmmAdapterIdLib.ERC_4626, SonicConstantsLib.TOKEN_stkscUSD, SonicConstantsLib.TOKEN_wstkscUSD);

        pools[i++] = _makePoolData(SonicConstantsLib.TOKEN_wstkscETH, AmmAdapterIdLib.ERC_4626, SonicConstantsLib.TOKEN_wstkscETH, SonicConstantsLib.TOKEN_stkscETH);
        pools[i++] =
            _makePoolData(SonicConstantsLib.POOL_SHADOW_CL_scETH_stkscETH_250, AmmAdapterIdLib.UNISWAPV3, SonicConstantsLib.TOKEN_stkscETH, SonicConstantsLib.TOKEN_scETH);

        pools[i++] = _makePoolData(SonicConstantsLib.POOL_SWAPX_CL_wS_OS, AmmAdapterIdLib.ALGEBRA_V4, SonicConstantsLib.TOKEN_OS, SonicConstantsLib.TOKEN_wS);
        pools[i++] = _makePoolData(SonicConstantsLib.TOKEN_wOS, AmmAdapterIdLib.ERC_4626, SonicConstantsLib.TOKEN_wOS, SonicConstantsLib.TOKEN_OS);

        pools[i++] = _makePoolData(SonicConstantsLib.SILO_VAULT_25_wS, AmmAdapterIdLib.ERC_4626, SonicConstantsLib.SILO_VAULT_25_wS, SonicConstantsLib.TOKEN_wS);
        pools[i++] = _makePoolData(
            SonicConstantsLib.POOL_BEETS_V3_SILO_VAULT_25_wS_anS, AmmAdapterIdLib.BALANCER_V3_STABLE, SonicConstantsLib.TOKEN_anS, SonicConstantsLib.SILO_VAULT_25_wS
        );
        pools[i++] = _makePoolData(SonicConstantsLib.TOKEN_wanS, AmmAdapterIdLib.ERC_4626, SonicConstantsLib.TOKEN_wanS, SonicConstantsLib.TOKEN_anS);

        pools[i++] = _makePoolData(SonicConstantsLib.POOL_SWAPX_CL_frxUSD_scUSD, AmmAdapterIdLib.ALGEBRA_V4, SonicConstantsLib.TOKEN_frxUSD, SonicConstantsLib.TOKEN_scUSD);
        pools[i++] =
            _makePoolData(SonicConstantsLib.POOL_SWAPX_CL_sfrxUSD_frxUSD, AmmAdapterIdLib.ALGEBRA_V4, SonicConstantsLib.TOKEN_sfrxUSD, SonicConstantsLib.TOKEN_frxUSD);

        pools[i++] =
            _makePoolData(SonicConstantsLib.POOL_SHADOW_CL_x33_SHADOW, AmmAdapterIdLib.UNISWAPV3, SonicConstantsLib.TOKEN_x33, SonicConstantsLib.TOKEN_SHADOW);
        
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_EQUALIZER_wS_DIAMONDS, AmmAdapterIdLib.SOLIDLY, SonicConstantsLib.TOKEN_DIAMONDS, SonicConstantsLib.TOKEN_wS);

        pools[i++] = _makePoolData(SonicConstantsLib.POOL_PENDLE_PT_aUSDC_14AUG2025, AmmAdapterIdLib.PENDLE, SonicConstantsLib.TOKEN_PT_aUSDC_14AUG2025, SonicConstantsLib.TOKEN_USDC);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_PENDLE_PT_wstkscUSD_29MAY2025, AmmAdapterIdLib.PENDLE, SonicConstantsLib.TOKEN_PT_wstkscUSD_29MAY2025, SonicConstantsLib.TOKEN_stkscUSD);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_PENDLE_PT_stS_29MAY2025, AmmAdapterIdLib.PENDLE, SonicConstantsLib.TOKEN_PT_stS_29MAY2025, SonicConstantsLib.TOKEN_stS);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_SWAPX_CL_bUSDCe20_wstkscUSD, AmmAdapterIdLib.ALGEBRA_V4, SonicConstantsLib.TOKEN_bUSDCe20, SonicConstantsLib.TOKEN_wstkscUSD);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_BEETS_BeetsFragmentsS1_stS, AmmAdapterIdLib.BALANCER_WEIGHTED, SonicConstantsLib.TOKEN_BeetsFragmentsS1, SonicConstantsLib.TOKEN_stS);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_SWAPX_CL_aSonUSDC_wstkscUSD, AmmAdapterIdLib.ALGEBRA_V4, SonicConstantsLib.TOKEN_aUSDC, SonicConstantsLib.TOKEN_wstkscUSD);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_SHADOW_CL_WBTC_WETH, AmmAdapterIdLib.UNISWAPV3, SonicConstantsLib.TOKEN_wBTC, SonicConstantsLib.TOKEN_wETH);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_PENDLE_PT_scUSD_14AUG2025, AmmAdapterIdLib.PENDLE, SonicConstantsLib.TOKEN_PT_Silo_46_scUSD_14AUG2025, SonicConstantsLib.TOKEN_scUSD);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_PT_Silo_20_USDC_17JUL2025, AmmAdapterIdLib.PENDLE, SonicConstantsLib.TOKEN_PT_Silo_20_USDC_17JUL2025, SonicConstantsLib.TOKEN_USDC);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_SHADOW_wETH_SILO, AmmAdapterIdLib.SOLIDLY, SonicConstantsLib.TOKEN_SILO, SonicConstantsLib.TOKEN_wETH);
        pools[i++] = _makePoolData(SonicConstantsLib.POOL_ALGEBRA_beS_OS, AmmAdapterIdLib.ALGEBRA_V4, SonicConstantsLib.TOKEN_beS, SonicConstantsLib.TOKEN_OS); // 40

        pools[i++] = _makePoolData(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD, AmmAdapterIdLib.ERC_4626, SonicConstantsLib.WRAPPED_METAVAULT_metaUSD, SonicConstantsLib.METAVAULT_metaUSD); // 41
        pools[i++] = _makePoolData(SonicConstantsLib.WRAPPED_METAVAULT_metaS, AmmAdapterIdLib.ERC_4626, SonicConstantsLib.WRAPPED_METAVAULT_metaS, SonicConstantsLib.METAVAULT_metaS); // 42

        // dynamic route: tokenIn is equal to tokenOut (actual tokenOut is selected on the fly)
        pools[i++] = _makePoolData(SonicConstantsLib.METAVAULT_metaUSD, AmmAdapterIdLib.META_VAULT, SonicConstantsLib.METAVAULT_metaUSD, SonicConstantsLib.METAVAULT_metaUSD); // 43
        // dynamic route: tokenIn is equal to tokenOut (actual tokenOut is selected on the fly)
        pools[i++] = _makePoolData(SonicConstantsLib.METAVAULT_metaS, AmmAdapterIdLib.META_VAULT, SonicConstantsLib.METAVAULT_metaS, SonicConstantsLib.METAVAULT_metaS); // 44

        pools[i++] = _makePoolData(SonicConstantsLib.POOL_SHADOW_CL_USDC_EUL, AmmAdapterIdLib.UNISWAPV3, SonicConstantsLib.TOKEN_EUL, SonicConstantsLib.TOKEN_USDC); // 45
        //endregion ----- Pools ----
    }

    function farms() public view returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](64);
        uint i;

        _farms[i++] = SonicFarmMakerLib._makeBeetsStableFarm(SonicConstantsLib.BEETS_GAUGE_wS_stS); //0
        _farms[i++] = SonicFarmMakerLib._makeBeetsStableFarm(SonicConstantsLib.BEETS_GAUGE_USDC_scUSD); //1
        _farms[i++] = SonicFarmMakerLib._makeEqualizerFarm(SonicConstantsLib.EQUALIZER_GAUGE_USDC_WETH);
        _farms[i++] = SonicFarmMakerLib._makeEqualizerFarm(SonicConstantsLib.EQUALIZER_GAUGE_wS_stS);
        _farms[i++] = SonicFarmMakerLib._makeEqualizerFarm(SonicConstantsLib.EQUALIZER_GAUGE_wS_USDC);
        _farms[i++] = SonicFarmMakerLib._makeEqualizerFarm(SonicConstantsLib.EQUALIZER_GAUGE_USDC_scUSD);
        _farms[i++] = SonicFarmMakerLib._makeBeetsWeightedFarm(SonicConstantsLib.BEETS_GAUGE_scUSD_stS);
        _farms[i++] = SonicFarmMakerLib._makeEqualizerFarm(SonicConstantsLib.EQUALIZER_GAUGE_wS_GOGLZ);
        _farms[i++] = SonicFarmMakerLib._makeIchiSwapXFarm(SonicConstantsLib.SWAPX_GAUGE_ICHI_SACRA_wS);
        _farms[i++] = SonicFarmMakerLib._makeIchiSwapXFarm(SonicConstantsLib.SWAPX_GAUGE_ICHI_wS_SACRA);
        _farms[i++] = SonicFarmMakerLib._makeIchiSwapXFarm(SonicConstantsLib.SWAPX_GAUGE_ICHI_stS_wS);
        _farms[i++] = SonicFarmMakerLib._makeIchiSwapXFarm(SonicConstantsLib.SWAPX_GAUGE_ICHI_wS_stS);
        _farms[i++] = SonicFarmMakerLib._makeIchiSwapXFarm(SonicConstantsLib.SWAPX_GAUGE_ICHI_SACRA_GEM_1_wS);
        _farms[i++] = SonicFarmMakerLib._makeIchiSwapXFarm(SonicConstantsLib.SWAPX_GAUGE_ICHI_wS_SACRA_GEM_1);
        _farms[i++] = SonicFarmMakerLib._makeSwapXFarm(SonicConstantsLib.SWAPX_GAUGE_USDC_scUSD);
        _farms[i++] = SonicFarmMakerLib._makeSwapXFarm(SonicConstantsLib.SWAPX_GAUGE_wS_GOGLZ);
        _farms[i++] = SonicFarmMakerLib._makeSwapXFarm(SonicConstantsLib.SWAPX_GAUGE_AUR_auUSDC);
        _farms[i++] = SonicFarmMakerLib._makeBeetsWeightedFarm(SonicConstantsLib.BEETS_GAUGE_USDC_stS);
        _farms[i++] =
            SonicFarmMakerLib._makeGammaUniswapV3MerklFarm(SonicConstantsLib.ALM_GAMMA_UNISWAPV3_wS_USDC_3000, ALMPositionNameLib.NARROW, SonicConstantsLib.TOKEN_wS);
        _farms[i++] =
            SonicFarmMakerLib._makeGammaUniswapV3MerklFarm(SonicConstantsLib.ALM_GAMMA_UNISWAPV3_wS_WETH_3000, ALMPositionNameLib.NARROW, SonicConstantsLib.TOKEN_wS);
        _farms[i++] =
            SonicFarmMakerLib._makeGammaUniswapV3MerklFarm(SonicConstantsLib.ALM_GAMMA_UNISWAPV3_USDC_WETH_500, ALMPositionNameLib.NARROW, SonicConstantsLib.TOKEN_wS);
        _farms[i++] =
            SonicFarmMakerLib._makeGammaUniswapV3MerklFarm(SonicConstantsLib.ALM_GAMMA_UNISWAPV3_USDC_scUSD_100, ALMPositionNameLib.STABLE, SonicConstantsLib.TOKEN_wS);
        _farms[i++] = SonicFarmMakerLib._makeSiloFarm(SonicConstantsLib.SILO_GAUGE_wS_008);
        _farms[i++] = SonicFarmMakerLib._makeSiloFarm(SonicConstantsLib.SILO_GAUGE_wS_020);
        _farms[i++] = SonicFarmMakerLib._makeIchiSwapXFarm(SonicConstantsLib.SWAPX_GAUGE_ICHI_sfrxUSD_frxUSD); // farm 24
        _farms[i++] = SonicFarmMakerLib._makeALMShadowFarm(SonicConstantsLib.SHADOW_GAUGE_CL_wS_WETH, ALMLib.ALGO_FILL_UP, 3000, 1200);
        _farms[i++] = SonicFarmMakerLib._makeALMShadowFarm(SonicConstantsLib.SHADOW_GAUGE_CL_wS_WETH, ALMLib.ALGO_FILL_UP, 1500, 600);
        _farms[i++] = SonicFarmMakerLib._makeALMShadowFarm(SonicConstantsLib.SHADOW_GAUGE_CL_wS_USDC, ALMLib.ALGO_FILL_UP, 3000, 1200);
        _farms[i++] = SonicFarmMakerLib._makeALMShadowFarm(SonicConstantsLib.SHADOW_GAUGE_CL_wS_USDC, ALMLib.ALGO_FILL_UP, 1500, 600);
        _farms[i++] = SonicFarmMakerLib._makeALMShadowFarm(SonicConstantsLib.SHADOW_GAUGE_CL_SACRA_scUSD_20000, ALMLib.ALGO_FILL_UP, 120000, 40000);
        _farms[i++] = SonicFarmMakerLib._makeALMShadowFarm(SonicConstantsLib.SHADOW_GAUGE_CL_SACRA_scUSD_20000, ALMLib.ALGO_FILL_UP, 800, 400);
        _farms[i++] = SonicFarmMakerLib._makeGammaEqualizerFarm(SonicConstantsLib.ALM_GAMMA_EQUALIZER_wS_USDC, ALMPositionNameLib.NARROW, SonicConstantsLib.EQUALIZER_GAUGE_GAMMA_wS_USDC);
        _farms[i++] = SonicFarmMakerLib._makeGammaEqualizerFarm(SonicConstantsLib.ALM_GAMMA_EQUALIZER_WETH_wS, ALMPositionNameLib.NARROW, SonicConstantsLib.EQUALIZER_GAUGE_GAMMA_WETH_wS);
        _farms[i++] = SonicFarmMakerLib._makeGammaEqualizerFarm(SonicConstantsLib.ALM_GAMMA_EQUALIZER_USDC_WETH, ALMPositionNameLib.NARROW, SonicConstantsLib.EQUALIZER_GAUGE_GAMMA_USDC_WETH);
        _farms[i++] = SonicFarmMakerLib._makeIchiEqualizerFarm(SonicConstantsLib.ALM_ICHI_EQUALIZER_USDC_wS, SonicConstantsLib.EQUALIZER_GAUGE_ICHI_USDC_wS);
        _farms[i++] = SonicFarmMakerLib._makeIchiEqualizerFarm(SonicConstantsLib.ALM_ICHI_EQUALIZER_wS_USDC, SonicConstantsLib.EQUALIZER_GAUGE_ICHI_wS_USDC);
        _farms[i++] = SonicFarmMakerLib._makeIchiEqualizerFarm(SonicConstantsLib.ALM_ICHI_EQUALIZER_WETH_USDC, SonicConstantsLib.EQUALIZER_GAUGE_ICHI_WETH_USDC);
        _farms[i++] = SonicFarmMakerLib._makeIchiEqualizerFarm(SonicConstantsLib.ALM_ICHI_EQUALIZER_wS_WETH, SonicConstantsLib.EQUALIZER_GAUGE_ICHI_wS_WETH);
        _farms[i++] = SonicFarmMakerLib._makeIchiEqualizerFarm(SonicConstantsLib.ALM_ICHI_EQUALIZER_WETH_wS, SonicConstantsLib.EQUALIZER_GAUGE_ICHI_WETH_wS);
        _farms[i++] = SonicFarmMakerLib._makeIchiEqualizerFarm(SonicConstantsLib.ALM_ICHI_EQUALIZER_USDC_WETH, SonicConstantsLib.EQUALIZER_GAUGE_ICHI_USDC_WETH);
        _farms[i++] = SonicFarmMakerLib._makeIchiSwapXFarm(SonicConstantsLib.SWAPX_GAUGE_ICHI_bUSDCe20_wstkscUSD); // farm 40
        _farms[i++] = SonicFarmMakerLib._makeIchiSwapXFarm(SonicConstantsLib.SWAPX_GAUGE_ICHI_aSonUSDC_wstkscUSD); // farm 41
        _farms[i++] = SonicFarmMakerLib._makeSiloManagedFarm(SonicConstantsLib.SILO_MANAGED_VAULT_S_Varlamore); // farm 42
        _farms[i++] = SonicFarmMakerLib._makeSiloManagedFarm(SonicConstantsLib.SILO_MANAGED_VAULT_USDC_Apostro); // farm 43
        _farms[i++] = SonicFarmMakerLib._makeSiloManagedFarm(SonicConstantsLib.SILO_MANAGED_VAULT_USDC_Re7); // farm 44
        _farms[i++] = SonicFarmMakerLib._makeSiloManagedFarm(SonicConstantsLib.SILO_MANAGED_VAULT_scUSD_Re7); // farm 45
        _farms[i++] = SonicFarmMakerLib._makeSiloManagedFarm(SonicConstantsLib.SILO_MANAGED_VAULT_USDC_Varlamore); // farm 46
        _farms[i++] = SonicFarmMakerLib._makeSiloManagedFarm(SonicConstantsLib.SILO_MANAGED_VAULT_USDC_Greenhouse); // farm 47
        _farms[i++] = SonicFarmMakerLib._makeSiloManagedFarm(SonicConstantsLib.SILO_MANAGED_VAULT_S_Greenhouse); // farm 48
        _farms[i++] = SonicFarmMakerLib._makeSiloManagedFarm(SonicConstantsLib.SILO_MANAGED_VAULT_S_Apostro); // farm 49
        _farms[i++] = SonicFarmMakerLib._makeSiloManagedFarm(SonicConstantsLib.SILO_MANAGED_VAULT_S_Re7); // farm 50
        _farms[i++] = SonicFarmMakerLib._makeSiloManagedFarm(SonicConstantsLib.SILO_MANAGED_VAULT_scUSD_Varlamore); // farm 51

        _farms[i++] = SonicFarmMakerLib._makeSiloFarm(SonicConstantsLib.SILO_GAUGE_wS_054, SonicConstantsLib.SILO_VAULT_54_S, SonicConstantsLib.TOKEN_wOS); // farm 52
        _farms[i++] = SonicFarmMakerLib._makeSiloALMFarm(
            SonicConstantsLib.SILO_VAULT_121_WMETAUSD,
            SonicConstantsLib.SILO_VAULT_121_USDC,
            SonicConstantsLib.BEETS_VAULT,
            SonicConstantsLib.SILO_LENS
        ); // farm 53
        _farms[i++] = SonicFarmMakerLib._makeSiloALMFarm(
            SonicConstantsLib.SILO_VAULT_125_WMETAUSD,
            SonicConstantsLib.SILO_VAULT_125_scUSD,
            SonicConstantsLib.BEETS_VAULT,
            SonicConstantsLib.SILO_LENS
        ); // farm 54
        _farms[i++] = SonicFarmMakerLib._makeSiloALMFarm(
            SonicConstantsLib.SILO_VAULT_128_WMETAS,
            SonicConstantsLib.SILO_VAULT_128_S,
            SonicConstantsLib.BEETS_VAULT,
            SonicConstantsLib.SILO_LENS
        ); // farm 55

        _farms[i++] = SonicFarmMakerLib._makeAaveMerklFarm(SonicConstantsLib.STABILITY_MARKET_SONIC_wS); // farm 56
        _farms[i++] = SonicFarmMakerLib._makeAaveMerklFarm(SonicConstantsLib.STABILITY_MARKET_SONIC_USDC); // farm 57
        _farms[i++] = SonicFarmMakerLib._makeAaveMerklFarm(SonicConstantsLib.STABILITY_MARKET_SONIC_scUSD); // farm 58
        _farms[i++] = SonicFarmMakerLib._makeAaveMerklFarm(SonicConstantsLib.STABILITY_CREDIX_MARKET_SONIC_wS); // farm 59
        _farms[i++] = SonicFarmMakerLib._makeAaveMerklFarm(SonicConstantsLib.STABILITY_CREDIX_MARKET_SONIC_USDC); // farm 60
        _farms[i++] = SonicFarmMakerLib._makeAaveMerklFarm(SonicConstantsLib.STABILITY_CREDIX_MARKET_SONIC_scUSD); // farm 61

        _farms[i++] = SonicFarmMakerLib._makeEulerMerklFarm(SonicConstantsLib.EULER_MERKL_USDC_MEV_Capital); //62
        _farms[i++] = SonicFarmMakerLib._makeEulerMerklFarm(SonicConstantsLib.EULER_MERKL_USDC_Re7_Labs); //63

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
