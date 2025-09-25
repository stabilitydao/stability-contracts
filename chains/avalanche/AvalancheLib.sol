// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SiloMerklFarmStrategy} from "../../src/strategies/SiloMerklFarmStrategy.sol";
import {AaveStrategy} from "../../src/strategies/AaveStrategy.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {AvalancheConstantsLib} from "./AvalancheConstantsLib.sol";
import {AvalancheFarmMakerLib} from "./AvalancheFarmMakerLib.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {ChainlinkAdapter} from "../../src/adapters/ChainlinkAdapter.sol";
import {DeployAdapterLib} from "../../script/libs/DeployAdapterLib.sol";
import {EulerMerklFarmStrategy} from "../../src/strategies/EulerMerklFarmStrategy.sol";
import {EulerStrategy} from "../../src/strategies/EulerStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IPlatformDeployer} from "../../src/interfaces/IPlatformDeployer.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {PriceReader} from "../../src/core/PriceReader.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SiloManagedMerklFarmStrategy} from "../../src/strategies/SiloManagedMerklFarmStrategy.sol";
import {SiloStrategy} from "../../src/strategies/SiloStrategy.sol";
import {StrategyDeveloperLib} from "../../src/strategies/libs/StrategyDeveloperLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";

/// @dev Avalanche network [chainId: 43114] deploy library
//    ,---,                               ,--,                                       ,---,
//   '  .' \                            ,--.'|                                     ,--.' |
//  /  ;    '.                          |  | :                     ,---,           |  |  :
// :  :       \        .---.            :  : '                 ,-+-. /  |          :  :  :
// :  |   /\   \     /.  ./|   ,--.--.  |  ' |     ,--.--.    ,--.'|'   |   ,---.  :  |  |,--.   ,---.
// |  :  ' ;.   :  .-' . ' |  /       \ '  | |    /       \  |   |  ,"' |  /     \ |  :  '   |  /     \
// |  |  ;/  \   \/___/ \: | .--.  .-. ||  | :   .--.  .-. | |   | /  | | /    / ' |  |   /' : /    /  |
// '  :  | \  \ ,'.   \  ' .  \__\/: . .'  : |__  \__\/: . . |   | |  | |.    ' /  '  :  | | |.    ' / |
// |  |  '  '--'   \   \   '  ," .--.; ||  | '.'| ," .--.; | |   | |  |/ '   ; :__ |  |  ' | :'   ;   /|
// |  :  :          \   \    /  /  ,.  |;  :    ;/  /  ,.  | |   | |--'  '   | '.'||  :  :_:,''   |  / |
// |  | ,'           \   \ |;  :   .'   \  ,   /;  :   .'   \|   |/      |   :    :|  | ,'    |   :    |
// `--''              '---" |  ,     .-./---`-' |  ,     .-./'---'        \   \  / `--''       \   \  /
//                           `--`---'            `--`---'                  `----'               `----'
/// @author Alien Deployer (https://github.com/a17)
library AvalancheLib {
    function platformDeployParams() internal pure returns (IPlatformDeployer.DeployPlatformParams memory p) {
        p.multisig = AvalancheConstantsLib.MULTISIG;
        p.version = "2025.09.0-alpha";
        p.targetExchangeAsset = AvalancheConstantsLib.TOKEN_USDC;
        p.fee = 20_000;
    }

    function deployAndSetupInfrastructure(address platform) internal {
        IFactory factory = IFactory(IPlatform(platform).factory());
        IPriceReader priceReader = PriceReader(IPlatform(platform).priceReader());

        //region ----- Deploy and setup vault types -----
        factory.setVaultImplementation(VaultTypeLib.COMPOUNDING, address(new CVault()));
        //endregion -- Deploy and setup vault types -----

        //region ----- Deploy and setup oracle adapters -----
        // Chainlink
        {
            Proxy proxy = new Proxy();
            proxy.initProxy(address(new ChainlinkAdapter()));
            ChainlinkAdapter chainlinkAdapter = ChainlinkAdapter(address(proxy));
            chainlinkAdapter.initialize(platform);
            address[] memory assets = new address[](5);
            assets[0] = AvalancheConstantsLib.TOKEN_USDC;
            assets[1] = AvalancheConstantsLib.TOKEN_USDT;
            assets[2] = AvalancheConstantsLib.TOKEN_WBTC;
            assets[3] = AvalancheConstantsLib.TOKEN_WETH;
            assets[4] = AvalancheConstantsLib.TOKEN_WAVAX;
            address[] memory priceFeeds = new address[](5);
            priceFeeds[0] = AvalancheConstantsLib.ORACLE_CHAINLINK_USDC_USD;
            priceFeeds[1] = AvalancheConstantsLib.ORACLE_CHAINLINK_USDT_USD;
            priceFeeds[2] = AvalancheConstantsLib.ORACLE_CHAINLINK_WBTC_USD;
            priceFeeds[3] = AvalancheConstantsLib.ORACLE_CHAINLINK_ETH_USD;
            priceFeeds[4] = AvalancheConstantsLib.ORACLE_CHAINLINK_AVAX_USD;
            chainlinkAdapter.addPriceFeeds(assets, priceFeeds);
            priceReader.addAdapter(address(chainlinkAdapter));
        }
        //endregion -- Deploy and setup oracle adapters -----

        //region ----- Deploy AMM adapters -----
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.UNISWAPV3);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.ALGEBRA_V4);
        //endregion -- Deploy AMM adapters ----

        //region ----- Setup Swapper -----
        {
            (ISwapper.AddPoolData[] memory pools) = routes();
            ISwapper swapper = ISwapper(IPlatform(platform).swapper());
            swapper.addPools(pools, false);
        }
        //endregion

        //region ----- Add farms -----
        factory.addFarms(farms());
        //endregion

        //region ----- Add strategy available init params -----
        IFactory.StrategyAvailableInitParams memory p;
        // -------------- SiloStrategy
        p.initAddresses = new address[](1);
        p.initAddresses[0] = AvalancheConstantsLib.SILO_VAULT_USDC_125;
        p.initNums = new uint[](0); // not used
        p.initTicks = new int24[](0); // not used
        factory.setStrategyAvailableInitParams(StrategyIdLib.SILO, p);

        // -------------- EulerStrategy
        p.initAddresses = new address[](2);
        p.initAddresses[0] = AvalancheConstantsLib.EULER_VAULT_USDT_K3;
        p.initAddresses[1] = AvalancheConstantsLib.EULER_VAULT_USDC_RE7;
        p.initNums = new uint[](0); // not used
        p.initTicks = new int24[](0); // not used
        factory.setStrategyAvailableInitParams(StrategyIdLib.EULER, p);

        // -------------- AaveStrategy
        p.initAddresses = new address[](1);
        p.initAddresses[0] = AvalancheConstantsLib.AAVE_aAvaUSDC;
        p.initNums = new uint[](0); // not used
        p.initTicks = new int24[](0); // not used
        factory.setStrategyAvailableInitParams(StrategyIdLib.AAVE, p);

        //endregion -- Add strategy available init params -----

        //region ----- Deploy strategies  -----
        _addStrategyLogic(factory, StrategyIdLib.SILO, address(new SiloStrategy()), false);
        _addStrategyLogic(factory, StrategyIdLib.EULER, address(new EulerStrategy()), false);
        _addStrategyLogic(factory, StrategyIdLib.AAVE, address(new AaveStrategy()), false);
        _addStrategyLogic(factory, StrategyIdLib.EULER_MERKL_FARM, address(new EulerMerklFarmStrategy()), true);
        _addStrategyLogic(factory, StrategyIdLib.SILO_MANAGED_MERKL_FARM, address(new SiloManagedMerklFarmStrategy()), true);
        _addStrategyLogic(factory, StrategyIdLib.SILO_MERKL_FARM, address(new SiloMerklFarmStrategy()), true);
        //endregion

        //region ----- Add DeX aggregators -----
        //endregion
    }

    function routes() public pure returns (ISwapper.AddPoolData[] memory pools) {
        pools = new ISwapper.AddPoolData[](6);
        uint i;
        pools[i++] = _makePoolData(
            AvalancheConstantsLib.POOL_BLACKHOLE_CL_USDT_USDC,
            AmmAdapterIdLib.ALGEBRA_V4,
            AvalancheConstantsLib.TOKEN_USDC,
            AvalancheConstantsLib.TOKEN_USDT
        );
        pools[i++] = _makePoolData(
            AvalancheConstantsLib.POOL_BLACKHOLE_CL_USDT_USDC,
            AmmAdapterIdLib.ALGEBRA_V4,
            AvalancheConstantsLib.TOKEN_USDT,
            AvalancheConstantsLib.TOKEN_USDT
        );
        pools[i++] = _makePoolData(
            AvalancheConstantsLib.POOL_BLACKHOLE_CL_WAVAX_USDC,
            AmmAdapterIdLib.ALGEBRA_V4,
            AvalancheConstantsLib.TOKEN_WAVAX,
            AvalancheConstantsLib.TOKEN_USDC
        );
        pools[i++] = _makePoolData(
            AvalancheConstantsLib.POOL_BLACKHOLE_CL_BTCB_WAVAX,
            AmmAdapterIdLib.ALGEBRA_V4,
            AvalancheConstantsLib.TOKEN_BTCB,
            AvalancheConstantsLib.TOKEN_WAVAX
        );
        pools[i++] = _makePoolData(
            AvalancheConstantsLib.POOL_BLACKHOLE_CL_WETH_WAVAX,
            AmmAdapterIdLib.ALGEBRA_V4,
            AvalancheConstantsLib.TOKEN_WETH,
            AvalancheConstantsLib.TOKEN_WAVAX
        );
        pools[i++] = _makePoolData(
            AvalancheConstantsLib.POOL_BLACKHOLE_CL_AUSD_USDC,
            AmmAdapterIdLib.ALGEBRA_V4,
            AvalancheConstantsLib.TOKEN_AUSD,
            AvalancheConstantsLib.TOKEN_USDC
        );
    }

    function farms() public pure returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](12);
        uint i;
        _farms[i++] = AvalancheFarmMakerLib._makeEulerMerklFarm(AvalancheConstantsLib.EULER_VAULT_USDC_RE7, AvalancheConstantsLib.TOKEN_WAVAX); // 0
        _farms[i++] = AvalancheFarmMakerLib._makeEulerMerklFarm(AvalancheConstantsLib.EULER_VAULT_USDT_K3, AvalancheConstantsLib.TOKEN_WAVAX); // 1

        // set EUL as reward token instead of rEUL because rEUL has vesting period after which it's converted to EUL
        // address of rEUL is added as farm.addresses[2] instead
        _farms[i++] = AvalancheFarmMakerLib._makeEulerMerklFarm(AvalancheConstantsLib.EULER_VAULT_BTCB_RESERVOIR, AvalancheConstantsLib.TOKEN_EUL); // 2

        // set EUL as reward token instead of rEUL because rEUL has vesting period after which it's converted to EUL
        // address of rEUL is added as farm.addresses[2] instead
        _farms[i++] = AvalancheFarmMakerLib._makeEulerMerklFarm(AvalancheConstantsLib.EULER_VAULT_WBTC_RESERVOIR, AvalancheConstantsLib.TOKEN_EUL); // 3

        _farms[i++] = AvalancheFarmMakerLib._makeSiloManagedMerklFarm(AvalancheConstantsLib.SILO_MANAGED_VAULT_USDC_MEV); // 4
        _farms[i++] = AvalancheFarmMakerLib._makeSiloManagedMerklFarm(AvalancheConstantsLib.SILO_MANAGED_VAULT_BTCb_MEV); // 5
        _farms[i++] = AvalancheFarmMakerLib._makeSiloManagedMerklFarm(AvalancheConstantsLib.SILO_MANAGED_VAULT_AUSD_VARLAMOURE); // 6
        _farms[i++] = AvalancheFarmMakerLib._makeSiloManagedMerklFarm(AvalancheConstantsLib.SILO_MANAGED_VAULT_USDt_VARLAMOURE); // 7

        _farms[i++] = AvalancheFarmMakerLib._makeSiloMerklFarm(AvalancheConstantsLib.SILO_VAULT_BTCb_130, AvalancheConstantsLib.TOKEN_WAVAX, address(0), true); // 8
        _farms[i++] = AvalancheFarmMakerLib._makeSiloMerklFarm(AvalancheConstantsLib.SILO_VAULT_USDC_142, AvalancheConstantsLib.TOKEN_WAVAX, address(0), true); // 9
        _farms[i++] = AvalancheFarmMakerLib._makeSiloMerklFarm(AvalancheConstantsLib.SILO_VAULT_BTCb_121, AvalancheConstantsLib.TOKEN_WAVAX, address(0), true); // 10
        _farms[i++] = AvalancheFarmMakerLib._makeSiloMerklFarm(AvalancheConstantsLib.SILO_VAULT_USDC_129, AvalancheConstantsLib.TOKEN_WAVAX, address(0), true); // 11
    }

    function _makePoolData(
        address pool,
        string memory ammAdapterId,
        address tokenIn,
        address tokenOut
    ) internal pure returns (ISwapper.AddPoolData memory) {
        return ISwapper.AddPoolData({pool: pool, ammAdapterId: ammAdapterId, tokenIn: tokenIn, tokenOut: tokenOut});
    }

    function _addStrategyLogic(IFactory factory, string memory id, address implementation, bool farming) internal {
        factory.setStrategyImplementation(id, address(implementation));
    }

    function testChainDeployLib() external {}
}
