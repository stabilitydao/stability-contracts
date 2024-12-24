// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../src/interfaces/IPlatformDeployer.sol";
import "../src/interfaces/IFactory.sol";
import "../src/core/proxy/Proxy.sol";
import "../script/libs/LogDeployLib.sol";
import "../src/interfaces/ISwapper.sol";
import "../src/strategies/libs/StrategyIdLib.sol";
import "../src/adapters/libs/AmmAdapterIdLib.sol";
import "../src/adapters/ChainlinkAdapter.sol";
import "../script/libs/DeployAdapterLib.sol";
import "../src/strategies/CompoundFarmStrategy.sol";
import "../src/strategies/libs/StrategyDeveloperLib.sol";

/// @dev Ethereum network [chainId: 1] data library
///   EEEEEEEEEE   TTTTTTTTTT  HHH    HHH   EEEEEEEEEE   RRRRRRRR    EEEEEEEEEE   UU     UU   M       M
///   EEE              TTT     HHH    HHH   EEE          RR    RRR   EEE          UU     UU   MM     MM
///   EEE              TTT     HHHHHHHHHH   EEE          RRRRRRR     EEE          UU     UU   MM M M MM
///   EEEEEEEE         TTT     HHHHHHHHHH   EEEEEEEE     RRR   RR    EEEEEEEE     UU     UU   MM  M  MM
///   EEE              TTT     HHH    HHH   EEE          RR    RR    EEE          UU     UU   MM     MM
///   EEE              TTT     HHH    HHH   EEE          RR     RR   EEE          UU     UU   MM     MM
///   EEEEEEEEEE       TTT     HHH    HHH   EEEEEEEEEE   RR      RR  EEEEEEEEEE    UUUUUUU    MM     MM
/// @author Interlinker (https://github.com/Interlinker0115)
library EthereumLib {
    // initial addresses
    address public constant MULTISIG = 0xEb49018157bAF7F1B385657D10fF5a5a5F4BB4c9;

    // ERC20
    address public constant TOKEN_WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant TOKEN_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant TOKEN_USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant TOKEN_weETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    address public constant TOKEN_COMP = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
    address public constant TOKEN_wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant TOKEN_SHFL = 0x8881562783028F5c1BCB985d2283D5E170D88888;
    address public constant TOKEN_WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant TOKEN_EBTC = 0x661c70333AA1850CcDBAe82776Bb436A0fCfeEfB;

    // AMMs
    address public constant POOL_UNISWAPV3_USDC_WETH_500 = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address public constant POOL_UNISWAPV3_WETH_weETH_500 = 0x7A415B19932c0105c82FDB6b720bb01B0CC2CAe3;
    address public constant POOL_UNISWAPV3_wstETH_WETH_100 = 0x109830a1AAaD605BbF02a9dFA7B0B92EC2FB7dAa;
    address public constant POOL_UNISWAPV3_COMP_WETH_3000 = 0xea4Ba4CE14fdd287f380b55419B1C5b6c3f22ab6;
    address public constant POOL_UNISWAPV3_SHFL_USDC_3000 = 0xD0A4c8A1a14530C7C9EfDaD0BA37E8cF4204d230;
    address public constant POOL_UNISWAPV3_WBTC_EBTC_500 = 0xEf9b4FddD861aa2F00eE039C323b7FAbd7AFE239;

    // Oracles
    address public constant ORACLE_CHAINLINK_USDC_USD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address public constant ORACLE_CHAINLINK_USDT_USD = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address public constant ORACLE_CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    // Compound
    address public constant COMPOUND_COMET_USDC = 0xc3d688B66703497DAA19211EEdff47f25384cdc3;
    address public constant COMPOUND_COMET_WETH = 0xA17581A9E3356d9A858b789D68B4d866e593aE94;
    address public constant COMPOUND_COMET_REWARDS = 0x1B0e765F6224C21223AeA2af16c1C46E38885a40;

    // DeX aggregators
    address public constant ONE_INCH = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    function platformDeployParams() internal pure returns (IPlatformDeployer.DeployPlatformParams memory p) {
        p.multisig = MULTISIG;
        p.version = "24.06.0-alpha";
        p.buildingPermitToken = address(0);
        p.buildingPayPerVaultToken = TOKEN_WETH;
        p.networkName = "Ethereum";
        p.networkExtra = CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x7c85c6), bytes3(0xffffff)));
        p.targetExchangeAsset = TOKEN_USDC;
        p.gelatoAutomate = address(0);
        p.gelatoMinBalance = 1e18;
        p.gelatoDepositAmount = 2e18;
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

        //region ---- Deploy and setup vault types -----
        _addVaultType(factory, VaultTypeLib.COMPOUNDING, address(new CVault()), 1e17);
        //endregion -- Deploy and setup vault types -----

        // region -----Deploy and setup oracle adapters -----
        IPriceReader priceReader = PriceReader(IPlatform(platform).priceReader());
        //Chainlink
        {
            Proxy proxy = new Proxy();
            proxy.initProxy(address(new ChainlinkAdapter()));
            ChainlinkAdapter chainlinkAdapter = ChainlinkAdapter(address(proxy));
            chainlinkAdapter.initialize(platform);
            address[] memory assets = new address[](3);
            assets[0] = TOKEN_USDC;
            assets[1] = TOKEN_WETH;
            assets[2] = TOKEN_USDT;
            address[] memory priceFeeds = new address[](3);
            priceFeeds[0] = ORACLE_CHAINLINK_USDC_USD;
            priceFeeds[1] = ORACLE_CHAINLINK_ETH_USD;
            priceFeeds[2] = ORACLE_CHAINLINK_USDT_USD;
            chainlinkAdapter.addPriceFeeds(assets, priceFeeds);
            priceReader.addAdapter(address(chainlinkAdapter));
            LogDeployLib.logDeployAndSetupOracleAdapter("ChainLink", address(chainlinkAdapter), showLog);
        }
        //endregion -- Deploy and setup oracle adapters -----

        //region ---- Deploy AMM adapters -----
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.UNISWAPV3);
        LogDeployLib.logDeployAmmAdapters(platform, showLog);
        //endregion -- Deploy AMM adapters -----

        //region ---- Setup Swapper -----
        {
            (ISwapper.AddPoolData[] memory bcPools, ISwapper.AddPoolData[] memory pools) = routes();
            ISwapper swapper = ISwapper(IPlatform(platform).swapper());
            swapper.addBlueChipsPools(bcPools, false);
            swapper.addPools(pools, false);
            address[] memory tokenIn = new address[](3);
            tokenIn[0] = TOKEN_USDC;
            tokenIn[1] = TOKEN_WETH;
            tokenIn[2] = TOKEN_USDT;
            uint[] memory thresholdAmount = new uint[](3);
            thresholdAmount[0] = 1e3;
            thresholdAmount[1] = 1e12;
            thresholdAmount[2] = 1e3;
            swapper.setThresholds(tokenIn, thresholdAmount);
            LogDeployLib.logSetupSwapper(platform, showLog);
        }
        //endregion -- Setup Swapper -----

        //region ----- Add farms -----
        factory.addFarms(farms());
        LogDeployLib.logAddedFarms(address(factory), showLog);
        //engregion -- Add farms -----

        //region ---- Deploy strategy logics -----
        _addStrategyLogic(factory, StrategyIdLib.COMPOUND_FARM, address(new CompoundFarmStrategy()), true);
        LogDeployLib.logDeployStrategies(platform, showLog);
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
        //region ---- Blue Chip Pools -----
        bcPools = new ISwapper.AddPoolData[](2);
        bcPools[0] = _makePoolData(POOL_UNISWAPV3_USDC_WETH_500, AmmAdapterIdLib.UNISWAPV3, TOKEN_USDC, TOKEN_WETH);
        bcPools[1] = _makePoolData(POOL_UNISWAPV3_WETH_weETH_500, AmmAdapterIdLib.UNISWAPV3, TOKEN_WETH, TOKEN_weETH);
        //endregion -- Blue Chip Pools -----

        //region ---- Pools -----
        pools = new ISwapper.AddPoolData[](6);
        uint i;
        pools[i++] = _makePoolData(POOL_UNISWAPV3_USDC_WETH_500, AmmAdapterIdLib.UNISWAPV3, TOKEN_USDC, TOKEN_WETH);
        pools[i++] = _makePoolData(POOL_UNISWAPV3_WETH_weETH_500, AmmAdapterIdLib.UNISWAPV3, TOKEN_WETH, TOKEN_weETH);
        pools[i++] = _makePoolData(POOL_UNISWAPV3_wstETH_WETH_100, AmmAdapterIdLib.UNISWAPV3, TOKEN_wstETH, TOKEN_WETH);
        pools[i++] = _makePoolData(POOL_UNISWAPV3_COMP_WETH_3000, AmmAdapterIdLib.UNISWAPV3, TOKEN_COMP, TOKEN_WETH);
        pools[i++] = _makePoolData(POOL_UNISWAPV3_SHFL_USDC_3000, AmmAdapterIdLib.UNISWAPV3, TOKEN_SHFL, TOKEN_USDC);
        pools[i++] = _makePoolData(POOL_UNISWAPV3_WBTC_EBTC_500, AmmAdapterIdLib.UNISWAPV3, TOKEN_WBTC, TOKEN_EBTC);
        //endregion -- Pools -----
    }

    function farms() public pure returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](2);
        uint i;
        // [0]-[1]
        _farms[i++] = _makeCompoundFarm(COMPOUND_COMET_USDC);
        _farms[i++] = _makeCompoundFarm(COMPOUND_COMET_WETH);
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

    function testEthereumLib() external {}
}
