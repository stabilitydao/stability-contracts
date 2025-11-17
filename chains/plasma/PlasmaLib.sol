// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../src/strategies/AaveMerklFarmStrategy.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {ChainlinkAdapter} from "../../src/adapters/ChainlinkAdapter.sol";
import {DeployAdapterLib} from "../../script/libs/DeployAdapterLib.sol";
import {EulerMerklFarmStrategy} from "../../src/strategies/EulerMerklFarmStrategy.sol";
import {IBalancerAdapter} from "../../src/interfaces/IBalancerAdapter.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IPlatformDeployer} from "../../src/interfaces/IPlatformDeployer.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {PlasmaConstantsLib} from "./PlasmaConstantsLib.sol";
import {PlasmaFarmMakerLib} from "./PlasmaFarmMakerLib.sol";
import {PriceReader, IPlatform, IPriceReader} from "../../src/core/PriceReader.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {StrategyDeveloperLib} from "../../src/strategies/libs/StrategyDeveloperLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {AaveLeverageMerklFarmStrategy} from "../../src/strategies/AaveLeverageMerklFarmStrategy.sol";

library PlasmaLib {
    function platformDeployParams() internal pure returns (IPlatformDeployer.DeployPlatformParams memory p) {
        p.multisig = PlasmaConstantsLib.MULTISIG;
        p.version = "2025.10.1-alpha";
        p.targetExchangeAsset = PlasmaConstantsLib.TOKEN_USDT0;
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
            address[] memory assets = new address[](2);
            assets[0] = PlasmaConstantsLib.TOKEN_USDT0;
            assets[1] = PlasmaConstantsLib.TOKEN_WETH;
            address[] memory priceFeeds = new address[](2);
            priceFeeds[0] = PlasmaConstantsLib.ORACLE_CHAINLINK_USDT0_USD;
            priceFeeds[1] = PlasmaConstantsLib.ORACLE_CHAINLINK_ETH_USD;
            chainlinkAdapter.addPriceFeeds(assets, priceFeeds);
            priceReader.addAdapter(address(chainlinkAdapter));
        }
        //endregion -- Deploy and setup oracle adapters -----

        //region ----- Deploy AMM adapters -----
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.BALANCER_V3_RECLAMM);
        IBalancerAdapter(IPlatform(platform).ammAdapter(keccak256(bytes(AmmAdapterIdLib.BALANCER_V3_RECLAMM))).proxy)
        .setupHelpers(PlasmaConstantsLib.BALANCER_V3_ROUTER);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.UNISWAPV3);
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

        //region ----- Deploy strategies  -----
        factory.setStrategyImplementation(StrategyIdLib.AAVE_MERKL_FARM, address(new AaveMerklFarmStrategy()));
        factory.setStrategyImplementation(StrategyIdLib.AAVE_LEVERAGE_MERKL_FARM, address(new AaveLeverageMerklFarmStrategy()));
        //endregion

        //region ----- Add DeX aggregators -----
        //endregion
    }

    function routes() public pure returns (ISwapper.AddPoolData[] memory pools) {
        pools = new ISwapper.AddPoolData[](3);
        uint i;
        pools[i++] = _makePoolData(
            PlasmaConstantsLib.POOL_BALANCER_V3_RECLAMM_WXPL_USDT0,
            AmmAdapterIdLib.BALANCER_V3_RECLAMM,
            PlasmaConstantsLib.TOKEN_USDT0,
            PlasmaConstantsLib.TOKEN_WXPL
        );
        pools[i++] = _makePoolData(
            PlasmaConstantsLib.POOL_BALANCER_V3_RECLAMM_WXPL_USDT0,
            AmmAdapterIdLib.BALANCER_V3_RECLAMM,
            PlasmaConstantsLib.TOKEN_WXPL,
            PlasmaConstantsLib.TOKEN_USDT0
        );
        pools[i++] = _makePoolData(
            PlasmaConstantsLib.OKU_TRADE_POOL_USDT0_WETH,
            AmmAdapterIdLib.UNISWAPV3,
            PlasmaConstantsLib.TOKEN_WETH,
            PlasmaConstantsLib.TOKEN_USDT0
        );
    }

    function farms() public pure returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](1);
        uint i;

        _farms[i++] = PlasmaFarmMakerLib._makeAaveMerklFarm(PlasmaConstantsLib.AAVE_V3_POOL_USDT0); // farm 0

// todo new strategy is required
//        _farms[i++] = PlasmaFarmMakerLib._makeEulerMerklFarm(PlasmaConstantsLib.EULER_MERKL_USDT0_K3_CAPITAL, PlasmaConstantsLib.TOKEN_WXPL); // 0
//        _farms[i++] = PlasmaFarmMakerLib._makeEulerMerklFarm(PlasmaConstantsLib.EULER_MERKL_USDT0_RE7, PlasmaConstantsLib.TOKEN_WXPL); // 0

    }

    function _makePoolData(
        address pool,
        string memory ammAdapterId,
        address tokenIn,
        address tokenOut
    ) internal pure returns (ISwapper.AddPoolData memory) {
        return ISwapper.AddPoolData({pool: pool, ammAdapterId: ammAdapterId, tokenIn: tokenIn, tokenOut: tokenOut});
    }

    function testChainDeployLib() external {}

}