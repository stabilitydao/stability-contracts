// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../src/interfaces/IPlatformDeployer.sol";
import "../src/interfaces/IFactory.sol";
import "../src/interfaces/IPlatform.sol";
import "../src/core/proxy/Proxy.sol";
import "../src/adapters/ChainlinkAdapter.sol";
import "../script/libs/LogDeployLib.sol";
import "../script/libs/DeployAdapterLib.sol";
import "../src/adapters/libs/AmmAdapterIdLib.sol";
import "../src/interfaces/ISwapper.sol";
import "../src/strategies/libs/StrategyIdLib.sol";
import "../src/strategies/CompoundFarmStrategy.sol";
import "../src/strategies/libs/StrategyDeveloperLib.sol";

/// @dev Arbitrum network [chainId: 42161] data library
///   AAAAA  RRRR   BBBB    III TTTTTT RRRR   UU   UU MMMM   MMMM
///  AA   AA RR  RR BB  BB  III   TT   RR  RR UU   UU MM MM MM MM
///  AA   AA RRRR   BBBBB   III   TT   RRRR   UU   UU MM  MMM  MM
///  AAAAAAA RR  RR BB  BB  III   TT   RR  RR UU   UU MM       MM
///  AA   AA RR   RR BBBB   III   TT   RR   RR UUUUU  MM       MM
/// @author Interlinker (https://github.com/Interlinker0115)
library ArbitrumLib {
    // initial addresses
    address public constant MULTISIG =
        0xE28e3Ee2bD10328bC8A7299B83A80d2E1ddD8708;

    // ERC20
    address public constant TOKEN_ARB =
        0x912CE59144191C1204E64559FE8253a0e49E6548;
    address public constant TOKEN_WETH =
        0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address public constant TOKEN_USDC =
        0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address public constant TOKEN_USDT =
        0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address public constant TOKEN_DAI =
        0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address public constant TOKEN_USDCe =
        0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public constant TOKEN_WBTC =
        0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address public constant TOKEN_weETH =
        0x35751007a407ca6FEFfE80b3cB397736D2cf4dbe;
    address public constant TOKEN_frxETH =
        0x178412e79c25968a32e89b11f63B33F733770c2A;
    address public constant TOKEN_FRAX =
        0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F;
    address public constant TOKEN_wstETH =
        0x5979D7b546E38E414F7E9822514be443A4800529;
    address public constant TOKEN_PENDLE =
        0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8;
    address public constant TOKEN_LINK =
        0xf97f4df75117a78c1A5a0DBb814Af92458539FB4;
    address public constant TOKEN_COMP =
        0x354A6dA3fcde098F8389cad84b0182725c6C91dE;

    // AMMs
    address public constant POOL_UNISWAPV3_WBTC_WETH_500 =
        0x2f5e87C9312fa29aed5c179E456625D79015299c;
    address public constant POOL_UNISWAPV3_WETH_USDC_500 =
        0xC6962004f452bE9203591991D15f6b388e09E8D0;
    address public constant POOL_UNISWAPV3_WETH_ARB_500 =
        0xC6F780497A95e246EB9449f5e4770916DCd6396A;
    address public constant POOL_UNISWAPV3_wstETH_WETH_100 =
        0x35218a1cbaC5Bbc3E57fd9Bd38219D37571b3537;
    address public constant POOL_UNISWAPV3_PENDLE_WETH_3000 =
        0xdbaeB7f0DFe3a0AAFD798CCECB5b22E708f7852c;
    address public constant POOL_UNISWAPV3_WETH_LINK_3000 =
        0x468b88941e7Cc0B88c1869d68ab6b570bCEF62Ff;
    address public constant POOL_UNISWAPV3_ARB_USDC_500 =
        0xcDa53B1F66614552F834cEeF361A8D12a0B8DaD8;
    address public constant POOL_STRYKE_WBTC_USDC_500 =
        0x0E4831319A50228B9e450861297aB92dee15B44F;
    address public constant POOL_CAMELOT_WETH_USDC_560 =
        0xB1026b8e7276e7AC75410F1fcbbe21796e8f7526;

    // Oracles
    address public constant ORACLE_CHAINLINK_USDC_USD =
        0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
    address public constant ORACLE_CHAINLINK_USDT_USD =
        0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7;
    address public constant ORACLE_CHAINLINK_DAI_USD =
        0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB;

    // Compound
    address public constant COMPOUND_COMET_USDCe =
        0xA5EDBDD9646f8dFF606d7448e414884C7d905dCA;
    address public constant COMPOUND_COMET_USDC =
        0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf;
    address public constant COMPOUND_COMET_REWARDS =
        0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae;

    // DeX aggregators
    address public constant ONE_INCH =
        0x1111111254EEB25477B68fb85Ed929f73A960582;

    function platformDeployParams()
        internal
        pure
        returns (IPlatformDeployer.DeployPlatformParams memory p)
    {
        p.multisig = MULTISIG;
        p.version = "24.06.0-alpha";
        p.buildingPermitToken = address(0);
        p.buildingPayPerVaultToken = TOKEN_ARB;
        p.networkName = "Arbitrum";
        p.networkExtra = CommonLib.bytesToBytes32(
            abi.encodePacked(bytes3(0x2959bc), bytes3(0x000000))
        );
        p.targetExchangeAsset = TOKEN_USDC;
        p.gelatoAutomate = address(0);
        p.gelatoMinBalance = 1e16;
        p.gelatoDepositAmount = 2e16;
    }

    function deployAndSetupInfrastructure(
        address platform,
        bool showLog
    ) internal {
        IFactory factory = IFactory(IPlatform(platform).factory());

        //region ----- Deployed Platform -----
        if (showLog) {
            console.log(
                "Deployed Statbility platform",
                IPlatform(platform).platformVersion()
            );
            console.log("Platform addres:", platform);
        }
        //endregion -- Deployed Platform ----

        //region ----- Deploy and setup vault types -----
        _addVaultType(
            factory,
            VaultTypeLib.COMPOUNDING,
            address(new CVault()),
            1e3
        );
        //endregion -- Deploy and setup valut types -----

        //region -----Deploy and setup oracle adapters -----
        IPriceReader priceReader = PriceReader(
            IPlatform(platform).priceReader()
        );
        //Chainlnk
        {
            Proxy proxy = new Proxy();
            proxy.initProxy(address(new ChainlinkAdapter()));
            ChainlinkAdapter chainlinkAdapter = ChainlinkAdapter(
                address(proxy)
            );
            chainlinkAdapter.initialize(platform);
            address[] memory assets = new address[](3);
            assets[0] = TOKEN_USDC;
            assets[1] = TOKEN_USDT;
            assets[2] = TOKEN_DAI;
            address[] memory priceFeeds = new address[](3);
            priceFeeds[0] = ORACLE_CHAINLINK_USDC_USD;
            priceFeeds[1] = ORACLE_CHAINLINK_USDT_USD;
            priceFeeds[2] = ORACLE_CHAINLINK_DAI_USD;
            chainlinkAdapter.addPriceFeeds(assets, priceFeeds);
            priceReader.addAdapter(address(chainlinkAdapter));
            LogDeployLib.logDeployAndSetupOracleAdapter(
                "ChainLink",
                address(chainlinkAdapter),
                showLog
            );
        }
        //endregion -- Deploy and setup oracle adapters -----

        //region ----- Deploy AMM adapters -----
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.UNISWAPV3);
        LogDeployLib.logDeployAmmAdapters(platform, showLog);
        //endregion -- Deploy AMM adapters -----

        //region ----- Setup Swapper -----
        {
            (
                ISwapper.AddPoolData[] memory bcPools,
                ISwapper.AddPoolData[] memory pools
            ) = routes();
            ISwapper swapper = ISwapper(IPlatform(platform).swapper());
            swapper.addBlueChipsPools(bcPools, false);
            swapper.addPools(pools, false);
            address[] memory tokenIn = new address[](8);
            tokenIn[0] = TOKEN_USDC;
            tokenIn[1] = TOKEN_USDT;
            tokenIn[2] = TOKEN_DAI;
            tokenIn[3] = TOKEN_USDCe;
            tokenIn[4] = TOKEN_WBTC;
            tokenIn[5] = TOKEN_weETH;
            tokenIn[6] = TOKEN_frxETH;

            tokenIn[7] = TOKEN_FRAX;
            uint[] memory thresholdAmount = new uint[](8);
            thresholdAmount[0] = 1e3;
            thresholdAmount[1] = 1e3;
            thresholdAmount[2] = 1e15;
            thresholdAmount[3] = 1e3;
            thresholdAmount[4] = 1e3;
            thresholdAmount[5] = 1e15;
            thresholdAmount[6] = 1e15;
            thresholdAmount[7] = 1e15;
            swapper.setThresholds(tokenIn, thresholdAmount);
            LogDeployLib.logSetupSwapper(platform, showLog);
        }
        //endregion -- Setup Swapper -----

        //region ----- Add farms -----
        factory.addFarms(farms());
        LogDeployLib.logAddedFarms(address(factory), showLog);
        //endregion -- Add farms -----

        //region ----- Deploy strategy logics -----
        _addStrategyLogic(
            factory,
            StrategyIdLib.COMPOUND_FARM,
            address(new CompoundFarmStrategy()),
            true
        );
        LogDeployLib.logDeployStrategies(platform, showLog);
        //endregion -- Deploy strategy logics -----

        //region ----- Add Dex aggregators -----
        address[] memory dexAggRouter = new address[](1);
        dexAggRouter[0] = ONE_INCH;
        IPlatform(platform).addDexAggregators(dexAggRouter);
        //endregion -- Add Dex aggregators -----
    }

    function routes()
        public
        pure
        returns (
            ISwapper.AddPoolData[] memory bcPools,
            ISwapper.AddPoolData[] memory pools
        )
    {
        //region ----- Blue Chip Pools -----
        bcPools = new ISwapper.AddPoolData[](3);
        bcPools[0] = _makePoolData(
            POOL_UNISWAPV3_WBTC_WETH_500,
            AmmAdapterIdLib.UNISWAPV3,
            TOKEN_WBTC,
            TOKEN_WETH
        );
        bcPools[0] = _makePoolData(
            POOL_UNISWAPV3_WETH_USDC_500,
            AmmAdapterIdLib.UNISWAPV3,
            TOKEN_WETH,
            TOKEN_USDC
        );
        bcPools[2] = _makePoolData(
            POOL_UNISWAPV3_WETH_ARB_500,
            AmmAdapterIdLib.UNISWAPV3,
            TOKEN_WETH,
            TOKEN_ARB
        );
        //endregion -- Blue Chip Pools ----

        //region ----- Pools ----
        pools = new ISwapper.AddPoolData[](6);
        uint i;
        // UniswapV3
        // pools[i++] = _makePoolData(
        //     POOL_UNISWAPV3_WBTC_WETH_500,
        //     AmmAdapterIdLib.UNISWAPV3,
        //     TOKEN_WBTC,
        //     TOKEN_WETH
        // );
        // pools[i++] = _makePoolData(
        //     POOL_UNISWAPV3_WETH_USDC_500,
        //     AmmAdapterIdLib.UNISWAPV3,
        //     TOKEN_WETH,
        //     TOKEN_USDC
        // );
        // pools[i++] = _makePoolData(
        //     POOL_UNISWAPV3_WETH_ARB_500,
        //     AmmAdapterIdLib.UNISWAPV3,
        //     TOKEN_WETH,
        //     TOKEN_ARB
        // );
        pools[i++] = _makePoolData(
            POOL_UNISWAPV3_wstETH_WETH_100,
            AmmAdapterIdLib.UNISWAPV3,
            TOKEN_wstETH,
            TOKEN_WETH
        );
        pools[i++] = _makePoolData(
            POOL_UNISWAPV3_PENDLE_WETH_3000,
            AmmAdapterIdLib.UNISWAPV3,
            TOKEN_PENDLE,
            TOKEN_WETH
        );
        pools[i++] = _makePoolData(
            POOL_UNISWAPV3_WETH_LINK_3000,
            AmmAdapterIdLib.UNISWAPV3,
            TOKEN_WETH,
            TOKEN_LINK
        );
        pools[i++] = _makePoolData(
            POOL_UNISWAPV3_ARB_USDC_500,
            AmmAdapterIdLib.UNISWAPV3,
            TOKEN_ARB,
            TOKEN_USDC
        );

        // StrykeSwap
        pools[i++] = _makePoolData(
            POOL_STRYKE_WBTC_USDC_500,
            AmmAdapterIdLib.UNISWAPV3,
            TOKEN_WBTC,
            TOKEN_USDC
        );
        pools[i++] = _makePoolData(
            POOL_CAMELOT_WETH_USDC_560,
            AmmAdapterIdLib.UNISWAPV3,
            TOKEN_WETH,
            TOKEN_USDC
        );
        //endregion -- Pools ----
    }

    function farms() public pure returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](2);
        uint i;

        _farms[i++] = _makeCompoundFarm(COMPOUND_COMET_USDCe);
        _farms[i++] = _makeCompoundFarm(COMPOUND_COMET_USDC);
    }

    function _makePoolData(
        address pool,
        string memory ammAdapterId,
        address tokenIn,
        address tokenOut
    ) internal pure returns (ISwapper.AddPoolData memory) {
        return
            ISwapper.AddPoolData({
                pool: pool,
                ammAdapterId: ammAdapterId,
                tokenIn: tokenIn,
                tokenOut: tokenOut
            });
    }

    function _makeCompoundFarm(
        address comet
    ) internal pure returns (IFactory.Farm memory) {
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

    function _addVaultType(
        IFactory factory,
        string memory id,
        address implementation,
        uint buildingPrice
    ) internal {
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

    function _addStrategyLogic(
        IFactory factory,
        string memory id,
        address implementation,
        bool farming
    ) internal {
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
    function testArbitrumLib() external {}
}
