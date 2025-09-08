// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AvalancheConstantsLib} from "./AvalancheConstantsLib.sol";
import {IPlatformDeployer} from "../../src/interfaces/IPlatformDeployer.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {PriceReader} from "../../src/core/PriceReader.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {ChainlinkAdapter} from "../../src/adapters/ChainlinkAdapter.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {DeployAdapterLib} from "../../script/libs/DeployAdapterLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {StrategyDeveloperLib} from "../../src/strategies/libs/StrategyDeveloperLib.sol";
import {EulerMerklFarmStrategy} from "../../src/strategies/EulerMerklFarmStrategy.sol";
import {SiloStrategy} from "../../src/strategies/SiloStrategy.sol";
import {EulerStrategy} from "../../src/strategies/EulerStrategy.sol";
import {AaveStrategy} from "../../src/strategies/AaveStrategy.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";

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
        //endregion -- Add strategy available init params -----

        //region ----- Deploy strategies  -----
        _addStrategyLogic(factory, StrategyIdLib.SILO, address(new SiloStrategy()), false);
        _addStrategyLogic(factory, StrategyIdLib.EULER, address(new EulerStrategy()), false);
        _addStrategyLogic(factory, StrategyIdLib.AAVE, address(new AaveStrategy()), false);
        _addStrategyLogic(factory, StrategyIdLib.EULER_MERKL_FARM, address(new EulerMerklFarmStrategy()), true);
        //endregion

        //region ----- Add DeX aggregators -----
        //endregion
    }

    function routes() public pure returns (ISwapper.AddPoolData[] memory pools) {
        pools = new ISwapper.AddPoolData[](5);
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
    }

    function farms() public pure returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](4);
        uint i;
        _farms[i++] = _makeEulerMerklFarm(AvalancheConstantsLib.EULER_VAULT_USDC_RE7, AvalancheConstantsLib.TOKEN_WAVAX); // 0
        _farms[i++] = _makeEulerMerklFarm(AvalancheConstantsLib.EULER_VAULT_USDT_K3, AvalancheConstantsLib.TOKEN_WAVAX); // 1
        _farms[i++] =
            _makeEulerMerklFarm(AvalancheConstantsLib.EULER_VAULT_BTCB_RESERVOIR, AvalancheConstantsLib.TOKEN_REUL); // 2
        _farms[i++] =
            _makeEulerMerklFarm(AvalancheConstantsLib.EULER_VAULT_WBTC_RESERVOIR, AvalancheConstantsLib.TOKEN_REUL); // 3
    }

    function _makeEulerMerklFarm(address vault, address rewardAsset) internal pure returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = address(0);
        farm.strategyLogicId = StrategyIdLib.EULER_MERKL_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = rewardAsset;
        farm.addresses = new address[](3);
        farm.addresses[0] = AvalancheConstantsLib.MERKL_DISTRIBUTOR;
        farm.addresses[1] = vault;
        farm.addresses[2] = AvalancheConstantsLib.TOKEN_REUL;
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

    function testChainDeployLib() external {}
}
