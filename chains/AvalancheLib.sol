// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../src/core/proxy/Proxy.sol";
import "../src/adapters/libs/AmmAdapterIdLib.sol";
import "../src/adapters/ChainlinkAdapter.sol";
import "../src/integrations/convex/IConvexRewardPool.sol";
import "../src/integrations/gamma/IHypervisor.sol";
import "../src/strategies/libs/StrategyIdLib.sol";
import "../src/strategies/libs/ALMPositionNameLib.sol";
import "../src/strategies/libs/StrategyDeveloperLib.sol";
import "../src/strategies/CompoundFarmStrategy.sol";
import "../src/strategies/GammaUniswapV3MerklFarmStrategy.sol";
import "../src/interfaces/IFactory.sol";
import "../src/interfaces/IPlatform.sol";
import "../src/interfaces/ISwapper.sol";
import "../src/interfaces/IPlatformDeployer.sol";
import "../script/libs/LogDeployLib.sol";
import "../script/libs/DeployAdapterLib.sol";

/// @dev Avalanche network [chainId: 43114] data library
///   AAAAA  V     V  AAAAA  L       AAAAA  N   N  CCCCC  H   H  EEEEE
///  AA   AA V     V AA   AA L      AA   AA NN  N CC   C H   H  EE
///  AAAAAAA V     V AAAAAAA L      AAAAAAA N N N CC     HHHHH  EEEE
///  AA   AA  V   V  AA   AA L      AA   AA N  NN CC   C H   H  EE
///  AA   AA   VVV   AA   AA LLLLLL AA   AA N   N  CCCCC H   H  EEEEE
/// @author Alien Deployer (https://github.com/a17)
library AvalancheLib {
    // initial addresses
    address public constant MULTISIG = 0xF564EBaC1182578398E94868bea1AbA6ba339652; // todo
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8; // todo

    // ERC20
    address public constant TOKEN_WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address public constant TOKEN_WETHe = 0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB;
    address public constant TOKEN_USDT = 0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7;
    address public constant TOKEN_USDC = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;

    // ---------------------------------- LayerZero-v2 https://docs.layerzero.network/v2/deployments/chains/avalanche
    address public constant LAYER_ZERO_V2_ENDPOINT = 0x1a44076050125825900e736c501f859c50fE728c;
    address public constant LAYER_ZERO_V2_SEND_ULN_302 = 0x197D1333DEA5Fe0D6600E9b396c7f1B1cFCc558a;
    address public constant LAYER_ZERO_V2_RECEIVE_ULN_302 = 0xbf3521d309642FA9B1c91A08609505BA09752c61;
    address public constant LAYER_ZERO_V2_READ_LIB_1002 = 0x8839D3f169f473193423b402BDC4B5c51daAABDc;
    address public constant LAYER_ZERO_V2_EXECUTOR = 0x90E595783E43eb89fF07f63d27B8430e6B44bD9c;
    address public constant LAYER_ZERO_V2_BLOCKED_MESSAGE_LIBRARY = 0x1ccbf0db9c192d969de57e25b3ff09a25bb1d862;
    address public constant LAYER_ZERO_V2_DEAD_DVN = 0x90cCA24D1338Bd284C25776D9c12f96764Bde5e1;


    function platformDeployParams() internal pure returns (IPlatformDeployer.DeployPlatformParams memory p) {
        p.multisig = MULTISIG;
        p.version = "24.06.0-alpha";
        p.buildingPermitToken = address(0);
        p.buildingPayPerVaultToken = TOKEN_USDC;
        p.networkName = "Avalanche";
        p.networkExtra = CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x2356f0), bytes3(0x000000)));
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
        //endregion -- Deployed Platform ----

        //region ----- Deploy and setup vault types -----
        _addVaultType(factory, VaultTypeLib.COMPOUNDING, address(new CVault()), 100e6);
        //endregion -- Deploy and setup vault types -----

        //region ----- Deploy and setup oracle adapters -----

// todo
//        IPriceReader priceReader = PriceReader(IPlatform(platform).priceReader());
//        // Chainlink
//        {
//            Proxy proxy = new Proxy();
//            proxy.initProxy(address(new ChainlinkAdapter()));
//            ChainlinkAdapter chainlinkAdapter = ChainlinkAdapter(address(proxy));
//            chainlinkAdapter.initialize(platform);
//            address[] memory assets = new address[](1);
//            assets[0] = TOKEN_USDC;
//            address[] memory priceFeeds = new address[](1);
//            priceFeeds[0] = ORACLE_CHAINLINK_USDC_USD;
//            chainlinkAdapter.addPriceFeeds(assets, priceFeeds);
//            priceReader.addAdapter(address(chainlinkAdapter));
//            LogDeployLib.logDeployAndSetupOracleAdapter("ChainLink", address(chainlinkAdapter), showLog);
//        }
        //endregion -- Deploy and setup oracle adapters -----

        //region ----- Deploy AMM adapters -----
// todo
//        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.UNISWAPV3);
//        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.CURVE);
//        LogDeployLib.logDeployAmmAdapters(platform, showLog);
        //endregion -- Deploy AMM adapters ----

        //region ----- Setup Swapper -----
        {
// todo
//            (ISwapper.AddPoolData[] memory bcPools, ISwapper.AddPoolData[] memory pools) = routes();
//            ISwapper swapper = ISwapper(IPlatform(platform).swapper());
//            swapper.addBlueChipsPools(bcPools, false);
//            swapper.addPools(pools, false);
//            address[] memory tokenIn = new address[](2);
//            tokenIn[0] = TOKEN_USDC;
//            tokenIn[1] = TOKEN_USDT;
//            uint[] memory thresholdAmount = new uint[](2);
//            thresholdAmount[0] = 1e3;
//            thresholdAmount[1] = 1e3;
//            swapper.setThresholds(tokenIn, thresholdAmount);
//            LogDeployLib.logSetupSwapper(platform, showLog);
        }
        //endregion -- Setup Swapper -----

        //region ----- Add farms -----
// todo
//        factory.addFarms(farms());
//        LogDeployLib.logAddedFarms(address(factory), showLog);
        //endregion -- Add farms -----

        //region ----- Deploy strategy logics -----
// todo
//        _addStrategyLogic(factory, StrategyIdLib.COMPOUND_FARM, address(new CompoundFarmStrategy()), true);
//        _addStrategyLogic(
//            factory, StrategyIdLib.GAMMA_UNISWAPV3_MERKL_FARM, address(new GammaUniswapV3MerklFarmStrategy()), true
//        );
//        LogDeployLib.logDeployStrategies(platform, showLog);
        //endregion -- Deploy strategy logics -----

        //region ----- Add DeX aggregators -----
// todo
//        address[] memory dexAggRouter = new address[](1);
//        dexAggRouter[0] = ONE_INCH;
//        IPlatform(platform).addDexAggregators(dexAggRouter);
        //endregion -- Add DeX aggregators -----
    }

    function routes()
        public
        pure
        returns (ISwapper.AddPoolData[] memory bcPools, ISwapper.AddPoolData[] memory pools)
    {
// todo
//        //region ----- BC pools ----
//        bcPools = new ISwapper.AddPoolData[](2);
//        bcPools[0] = _makePoolData(POOL_UNISWAPV3_USDC_USDT_100, AmmAdapterIdLib.UNISWAPV3, TOKEN_USDC, TOKEN_USDT);
//        bcPools[1] = _makePoolData(POOL_UNISWAPV3_WETH_USDC_500, AmmAdapterIdLib.UNISWAPV3, TOKEN_WETH, TOKEN_USDC);
//        //endregion -- BC pools ----
//
//        //region ----- Pools ----
//        pools = new ISwapper.AddPoolData[](9);
//        uint i;
//        // UniswapV3
//        pools[i++] = _makePoolData(POOL_UNISWAPV3_USDC_USDT_100, AmmAdapterIdLib.UNISWAPV3, TOKEN_USDC, TOKEN_USDT);
//        pools[i++] = _makePoolData(POOL_UNISWAPV3_WETH_USDC_500, AmmAdapterIdLib.UNISWAPV3, TOKEN_WETH, TOKEN_USDC);
//        pools[i++] = _makePoolData(POOL_UNISWAPV3_WETH_USDT_500, AmmAdapterIdLib.UNISWAPV3, TOKEN_USDT, TOKEN_WETH);
//        pools[i++] = _makePoolData(POOL_UNISWAPV3_WETH_wstETH_100, AmmAdapterIdLib.UNISWAPV3, TOKEN_wstETH, TOKEN_WETH);
//        pools[i++] = _makePoolData(POOL_UNISWAPV3_cbETH_WETH_500, AmmAdapterIdLib.UNISWAPV3, TOKEN_cbETH, TOKEN_WETH);
//        pools[i++] = _makePoolData(POOL_UNISWAPV3_WETH_COMP_10000, AmmAdapterIdLib.UNISWAPV3, TOKEN_COMP, TOKEN_WETH);
//
//        // BaseSwap
//        pools[i++] = _makePoolData(POOL_BASESWAP_USDC_USDbC_80, AmmAdapterIdLib.UNISWAPV3, TOKEN_USDbC, TOKEN_USDC);
//        pools[i++] = _makePoolData(POOL_BASESWAP_USDC_sFRAX_80, AmmAdapterIdLib.UNISWAPV3, TOKEN_sFRAX, TOKEN_USDC);
//        // pools[i++] = _makePoolData(POOL_BASESWAP_sfrxETH_WETH_80, AmmAdapterIdLib.UNISWAPV3, TOKEN_sfrxETH, TOKEN_WETH);
//
//        // update 15.06.2024
//        pools[i++] = _makePoolData(POOL_UNISWAPV3_USDC_UNI_10000, AmmAdapterIdLib.UNISWAPV3, TOKEN_UNI, TOKEN_USDC);
//
//        //endregion -- Pools ----
        return (bcPools, pools);
    }

    function farms() public view returns (IFactory.Farm[] memory _farms) {
// todo
//        _farms = new IFactory.Farm[](6);
//        uint i;
//
//        // [0]-[2]
//        _farms[i++] = _makeCompoundFarm(COMPOUND_COMET_USDC);
//        _farms[i++] = _makeCompoundFarm(COMPOUND_COMET_USDbC);
//        _farms[i++] = _makeCompoundFarm(COMPOUND_COMET_ETH);
//
//        // [3]-[5]
//        _farms[i++] =
//            _makeGammaUniswapV3MerklFarm(GAMMA_UNISWAPV3_cbETH_WETH_500_PEGGED, ALMPositionNameLib.PEGGED, TOKEN_UNI);
//        _farms[i++] = _makeGammaUniswapV3MerklFarm(
//            GAMMA_UNISWAPV3_WETH_wstETH_100_PEGGED, ALMPositionNameLib.PEGGED, TOKEN_wstETH
//        );
//        _farms[i++] =
//            _makeGammaUniswapV3MerklFarm(GAMMA_UNISWAPV3_USDC_USDT_100_STABLE, ALMPositionNameLib.STABLE, TOKEN_UNI);
        return _farms;
    }

    function _makePoolData(
        address pool,
        string memory ammAdapterId,
        address tokenIn,
        address tokenOut
    ) internal pure returns (ISwapper.AddPoolData memory) {
        return ISwapper.AddPoolData({pool: pool, ammAdapterId: ammAdapterId, tokenIn: tokenIn, tokenOut: tokenOut});
    }

//    function _makeCompoundFarm(address comet) internal pure returns (IFactory.Farm memory) {
//        IFactory.Farm memory farm;
//        farm.status = 0;
//        farm.strategyLogicId = StrategyIdLib.COMPOUND_FARM;
//        farm.rewardAssets = new address[](1);
//        farm.rewardAssets[0] = TOKEN_COMP;
//        farm.addresses = new address[](2);
//        farm.addresses[0] = comet;
//        farm.addresses[1] = COMPOUND_COMET_REWARDS;
//        farm.nums = new uint[](0);
//        farm.ticks = new int24[](0);
//        return farm;
//    }

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
