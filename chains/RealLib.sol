// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../script/libs/LogDeployLib.sol";
import {StrategyIdLib} from "../src/strategies/libs/StrategyIdLib.sol";
import {CommonLib} from "../src/core/libs/CommonLib.sol";
import {IPlatformDeployer} from "../src/interfaces/IPlatformDeployer.sol";
import {AmmAdapterIdLib} from "../src/adapters/libs/AmmAdapterIdLib.sol";
import {ISwapper} from "../src/interfaces/ISwapper.sol";
import {IFactory} from "../src/interfaces/IFactory.sol";
import {StrategyDeveloperLib} from "../src/strategies/libs/StrategyDeveloperLib.sol";
import {IPlatform} from "../src/interfaces/IPlatform.sol";
import {DeployAdapterLib} from "../script/libs/DeployAdapterLib.sol";
import {DiaAdapter} from "../src/adapters/DiaAdapter.sol";
import {ILiquidBoxFactory} from "../src/integrations/pearl/ILiquidBoxFactory.sol";
import {ILiquidBox} from "../src/integrations/pearl/ILiquidBox.sol";
import {IGaugeV2CL} from "../src/integrations/pearl/IGaugeV2CL.sol";
import {TridentPearlFarmStrategy} from "../src/strategies/TridentPearlFarmStrategy.sol";

/// @dev Re.al network [chainId: 111188] data library
/// ______            _
//  | ___ \          | |
//  | |_/ /___   __ _| |
//  |    // _ \ / _` | |
//  | |\ \  __/| (_| | |
//  \_| \_\___(_)__,_|_|
//
/// @author Alien Deployer (https://github.com/a17)
library RealLib {
    // initial addresses
    address public constant MULTISIG = 0x7B4388F4bD3A439E34a554EF67513112Bcd77Fba;

    // ERC20
    address public constant TOKEN_WREETH = 0x90c6E93849E06EC7478ba24522329d14A5954Df4; // Wrapped Real Ether
    address public constant TOKEN_DAI = 0x75d0cBF342060b14c2fC756fd6E717dFeb5B1B70;
    address public constant TOKEN_USTB = 0x83feDBc0B85c6e29B589aA6BdefB1Cc581935ECD;
    address public constant TOKEN_MORE = 0x25ea98ac87A38142561eA70143fd44c4772A16b6;
    address public constant TOKEN_PEARL = 0xCE1581d7b4bA40176f0e219b2CaC30088Ad50C7A;
    address public constant TOKEN_CVR = 0xB08F026f8a096E6d92eb5BcbE102c273A7a2d51C;
    address public constant TOKEN_UKRE = 0x835d3E1C0aA079C6164AAd21DCb23E60eb71AF48;
    address public constant TOKEN_RWA = 0x4644066f535Ead0cde82D209dF78d94572fCbf14;
    address public constant TOKEN_arcUSD = 0xAEC9e50e3397f9ddC635C6c429C8C7eca418a143;
    address public constant TOKEN_USDC = 0xc518A88c67CECA8B3f24c4562CB71deeB2AF86B7;
    address public constant TOKEN_SACRA = 0x6B2e0fACD2F2A8f407aC591067Ac06b5d29247E4;

    // CL AMMs
    // 21.10.2024: TVL $3.22M, APR 84.6%
    address public constant POOL_PEARL_arcUSD_USDC_100 = 0x22aC4821bBb8d1AC42eA7F0f32ed415F52577Ca1;
    // 21.10.2024: TVL $3.08M, APR 84.77%
    address public constant POOL_PEARL_MORE_USDC_100 = 0x701655595037dfe1e59E69446De009236F012405;
    // 21.10.2024: TVL $2.19M, APR 137.62%
    address public constant POOL_PEARL_UKRE_arcUSD_500 = 0x72c20EBBffaE1fe4E9C759b326D97763E218F9F6;
    // 21.10.2024: TVL $1.26M, APR 19.27%
    address public constant POOL_PEARL_CVR_PEARL_500 = 0xfA88A4a7fF6D776c3D0A637095d7a9a4ed813872;
    // 21.10.2024: TVL $824.08K, APR 103.98%
    address public constant POOL_PEARL_USDC_PEARL_10000 = 0x374a765309B6D5a123f32971dcA1E6CeF9fa0066;
    // 21.10.2024: TVL $658.69K, APR 128.66%
    address public constant POOL_PEARL_reETH_USDC_500 = 0x64F5eFB0f0643B654C96f77855DaFfe4C2FE0252;
    // 21.10.2024: TVL $605.13K, APR 60.84%
    address public constant POOL_PEARL_DAI_USDC_100 = 0x4f5c568F72369ff4Ce4e53d797985DFFBdA6FC71;
    // 21.10.2024: TVL $391.42K, APR 41.74%
    address public constant POOL_PEARL_MORE_USTB_100 = 0x6b1a34df762f1d3367e7e93AE5661c88CA848423;
    // 21.10.2024: TVL $297.46K, APR 72.69%
    address public constant POOL_PEARL_USTB_arcUSD_100 = 0xC6B3AaaAbf2f6eD6cF7fdFFfb0DaC45E10c4A5B3;
    // 21.10.2024: TVL $192.32K, APR 38.79%
    address public constant POOL_PEARL_DAI_USTB_100 = 0x727B8b6135dcFe1E18A2689aBBe776a6810E763c;
    // 21.10.2024: TVL $153.61K, APR 47.49%
    address public constant POOL_PEARL_USTB_reETH_3000 = 0x5dfa942B42841Dd18883838D8F4e5f7d8CEb5Eeb;
    // 21.10.2024: TVL $140.95K, APR 216.39%
    address public constant POOL_PEARL_RWA_reETH_3000 = 0x182d3F8e154EB43d5f361a39A2234A84508244c9;
    // 21.10.2024: TVL $87.46K, APR 121.94%
    address public constant POOL_PEARL_USTB_PEARL_10000 = 0x35BA384F9D30D68028898849ddBf5bda09bbE7EA;
    // 21.10.2024: TVL $78.34K, APR 0%
    address public constant POOL_PEARL_SACRA_reETH_10000 = 0x2EC05Ab55867719f433d8ab0a446C48003B3BE8F;

    // StableSwap AMMs
    address public constant POOL_PEARL_MORE_USDC = 0x1733720f30EF013539Fa2EcEE00671A60B66243D;
    address public constant POOL_PEARL_stRWA_RWA = 0xb28d015563c81dd66Ab781853c03B7B66aa46C1b;

    // VolatileV1 AMMs
    address public constant POOL_PEARL_USDC_PEARL = 0xAFb84DFe257cBA43d2f44B4367aDAc5a82775275;
    address public constant POOL_PEARL_arcUSD_PEARL = 0xd3Ae2AF8f1Fb00af2e363fe6592C19ABF9105FA9;

    // ALMs
    address public constant TRIDENT_LIQUID_BOX_FACTORY = 0xEfeFFa36b9FA787b500b2d18a3829271526023b1;

    // Oracles
    address public constant ORACLE_DIA_WREETH_USDC = 0xA2c62937987815A9Bb9d3b2F4580e629F9FA3Bc8;

    //noinspection NoReturn
    function platformDeployParams() internal pure returns (IPlatformDeployer.DeployPlatformParams memory p) {
        p.multisig = MULTISIG;
        p.version = "24.06.0-alpha";
        p.buildingPermitToken = address(0);
        p.buildingPayPerVaultToken = TOKEN_USDC;
        p.networkName = "Real";
        p.networkExtra = CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0xeeeeee), bytes3(0x000000)));
        p.targetExchangeAsset = TOKEN_USDC;
        p.gelatoAutomate = address(0);
        p.gelatoMinBalance = 1e16;
        p.gelatoDepositAmount = 2e16;
        p.fee = 6_000;
        p.feeShareVaultManager = 30_000;
        p.feeShareStrategyLogic = 30_000;
    }

    function deployAndSetupInfrastructure(address platform, bool showLog) internal {
        IFactory factory = IFactory(IPlatform(platform).factory());

        //region ----- Deployed Platform -----
        if (showLog) {
            console.log("Deployed Stability platform", IPlatform(platform).platformVersion());
            console.log("Platform address: ", platform);
        }
        //endregion -- Deployed Platform -----

        //region ----- Deploy and setup vault types -----
        _addVaultType(factory, VaultTypeLib.COMPOUNDING, address(new CVault()), 10e6);
        //endregion -- Deploy and setup vault types -----

        //region ----- Deploy and setup oracle adapters -----
        IPriceReader priceReader = PriceReader(IPlatform(platform).priceReader());
        // Dia
        {
            Proxy proxy = new Proxy();
            proxy.initProxy(address(new DiaAdapter()));
            DiaAdapter adapter = DiaAdapter(address(proxy));
            adapter.initialize(platform);
            address[] memory assets = new address[](1);
            assets[0] = TOKEN_WREETH;
            address[] memory priceFeeds = new address[](1);
            priceFeeds[0] = ORACLE_DIA_WREETH_USDC;
            adapter.addPriceFeeds(assets, priceFeeds);
            priceReader.addAdapter(address(adapter));
            LogDeployLib.logDeployAndSetupOracleAdapter("Dia", address(adapter), showLog);
        }
        //endregion -- Deploy and setup oracle adapters -----

        //region ----- Deploy AMM adapters -----
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.UNISWAPV3);
        LogDeployLib.logDeployAmmAdapters(platform, showLog);
        //endregion -- Deploy AMM adapters -----

        //region ----- Setup Swapper -----
        {
            (ISwapper.AddPoolData[] memory bcPools, ISwapper.AddPoolData[] memory pools) = routes();
            ISwapper swapper = ISwapper(IPlatform(platform).swapper());
            swapper.addBlueChipsPools(bcPools, false);
            swapper.addPools(pools, false);
            address[] memory tokenIn = new address[](3);
            tokenIn[0] = TOKEN_USDC;
            tokenIn[1] = TOKEN_PEARL;
            tokenIn[2] = TOKEN_MORE;
            // todo thresholds
            uint[] memory thresholdAmount = new uint[](3);
            thresholdAmount[0] = 1e4;
            thresholdAmount[1] = 1e12;
            thresholdAmount[2] = 1e15;
            swapper.setThresholds(tokenIn, thresholdAmount);
            LogDeployLib.logSetupSwapper(platform, showLog);
        }
        //endregion ----- Setup Swapper -----

        //region ----- Add farms -----
        factory.addFarms(farms());
        LogDeployLib.logAddedFarms(address(factory), showLog);
        //endregion -- Add farms -----

        //region ----- Deploy strategy logics -----
        _addStrategyLogic(factory, StrategyIdLib.TRIDENT_PEARL_FARM, address(new TridentPearlFarmStrategy()), true);
        LogDeployLib.logDeployStrategies(platform, showLog);
        //endregion -- Deploy strategy logics -----

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
        bcPools[0] = _makePoolData(POOL_PEARL_arcUSD_USDC_100, AmmAdapterIdLib.UNISWAPV3, TOKEN_arcUSD, TOKEN_USDC);
        bcPools[1] = _makePoolData(POOL_PEARL_reETH_USDC_500, AmmAdapterIdLib.UNISWAPV3, TOKEN_WREETH, TOKEN_USDC);
        //endregion -- BC pools ----

        //region ----- Pools ----
        pools = new ISwapper.AddPoolData[](11);
        uint i;
        pools[i++] = _makePoolData(POOL_PEARL_arcUSD_USDC_100, AmmAdapterIdLib.UNISWAPV3, TOKEN_USDC, TOKEN_arcUSD);
        pools[i++] = _makePoolData(POOL_PEARL_arcUSD_USDC_100, AmmAdapterIdLib.UNISWAPV3, TOKEN_arcUSD, TOKEN_USDC);
        pools[i++] = _makePoolData(POOL_PEARL_reETH_USDC_500, AmmAdapterIdLib.UNISWAPV3, TOKEN_WREETH, TOKEN_USDC);
        pools[i++] = _makePoolData(POOL_PEARL_MORE_USDC_100, AmmAdapterIdLib.UNISWAPV3, TOKEN_MORE, TOKEN_USDC);
        pools[i++] = _makePoolData(POOL_PEARL_UKRE_arcUSD_500, AmmAdapterIdLib.UNISWAPV3, TOKEN_UKRE, TOKEN_arcUSD);
        pools[i++] = _makePoolData(POOL_PEARL_CVR_PEARL_500, AmmAdapterIdLib.UNISWAPV3, TOKEN_CVR, TOKEN_PEARL);
        pools[i++] = _makePoolData(POOL_PEARL_USDC_PEARL_10000, AmmAdapterIdLib.UNISWAPV3, TOKEN_PEARL, TOKEN_USDC);
        pools[i++] = _makePoolData(POOL_PEARL_DAI_USDC_100, AmmAdapterIdLib.UNISWAPV3, TOKEN_DAI, TOKEN_USDC);
        pools[i++] = _makePoolData(POOL_PEARL_MORE_USTB_100, AmmAdapterIdLib.UNISWAPV3, TOKEN_USTB, TOKEN_MORE);
        pools[i++] = _makePoolData(POOL_PEARL_RWA_reETH_3000, AmmAdapterIdLib.UNISWAPV3, TOKEN_RWA, TOKEN_WREETH);
        pools[i++] = _makePoolData(POOL_PEARL_SACRA_reETH_10000, AmmAdapterIdLib.UNISWAPV3, TOKEN_SACRA, TOKEN_WREETH);
        //endregion -- Pools ----
    }

    function farms() public view returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](14);
        uint i;

        _farms[i++] = _makeTridentPearlFarm(POOL_PEARL_arcUSD_USDC_100);
        _farms[i++] = _makeTridentPearlFarm(POOL_PEARL_MORE_USDC_100);
        _farms[i++] = _makeTridentPearlFarm(POOL_PEARL_UKRE_arcUSD_500);
        _farms[i++] = _makeTridentPearlFarm(POOL_PEARL_CVR_PEARL_500);
        _farms[i++] = _makeTridentPearlFarm(POOL_PEARL_USDC_PEARL_10000);
        _farms[i++] = _makeTridentPearlFarm(POOL_PEARL_reETH_USDC_500);
        _farms[i++] = _makeTridentPearlFarm(POOL_PEARL_DAI_USDC_100);
        _farms[i++] = _makeTridentPearlFarm(POOL_PEARL_MORE_USTB_100);
        _farms[i++] = _makeTridentPearlFarm(POOL_PEARL_USTB_arcUSD_100);
        _farms[i++] = _makeTridentPearlFarm(POOL_PEARL_DAI_USTB_100);
        _farms[i++] = _makeTridentPearlFarm(POOL_PEARL_USTB_reETH_3000);
        _farms[i++] = _makeTridentPearlFarm(POOL_PEARL_USTB_PEARL_10000);
        _farms[i++] = _makeTridentPearlFarm(POOL_PEARL_RWA_reETH_3000);
        _farms[i++] = _makeTridentPearlFarm(POOL_PEARL_SACRA_reETH_10000);
    }

    function _makeTridentPearlFarm(address pool) internal view returns (IFactory.Farm memory) {
        address alm = ILiquidBoxFactory(TRIDENT_LIQUID_BOX_FACTORY).getBoxByPool(pool);
        address gauge = ILiquidBox(alm).gauge();
        address boxManager = ILiquidBoxFactory(TRIDENT_LIQUID_BOX_FACTORY).boxManager();

        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = pool;
        farm.strategyLogicId = StrategyIdLib.TRIDENT_PEARL_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = IGaugeV2CL(gauge).rewardToken();
        farm.addresses = new address[](3);
        farm.addresses[0] = alm;
        farm.addresses[1] = gauge;
        farm.addresses[2] = boxManager;
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
