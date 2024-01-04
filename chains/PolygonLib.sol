// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../src/core/proxy/Proxy.sol";
import "../src/adapters/libs/AmmAdapterIdLib.sol";
import "../src/adapters/ChainlinkAdapter.sol";
import "../src/strategies/libs/StrategyIdLib.sol";
import "../src/strategies/libs/GammaLib.sol";
import "../src/interfaces/IFactory.sol";
import "../src/interfaces/IPlatform.sol";
import "../src/interfaces/ISwapper.sol";
import "../script/libs/DeployLib.sol";
import "../script/libs/DeployAdapterLib.sol";
import "../script/libs/DeployStrategyLib.sol";

/// @dev Addresses, routes, farms, strategy logics, reward tokens, deploy function and other data for Polygon network
library PolygonLib {
    // initial addresses
    address public constant MULTISIG = 0x36780E69D38c8b175761c6C5F8eD42E61ee490E9; // team

    // ERC20
    address public constant TOKEN_PROFIT = 0x48469a0481254d5945E7E56c1Eb9861429c02f44;
    address public constant TOKEN_SDIV = 0x9844a1c30462B55cd383A2C06f90BB4171f9D4bB;
    address public constant TOKEN_USDCe = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address public constant TOKEN_WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address public constant TOKEN_WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public constant TOKEN_USDT = 0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    address public constant TOKEN_DAI = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address public constant TOKEN_WBTC = 0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6;
    address public constant TOKEN_QUICK = 0xB5C064F955D8e7F38fE0460C556a72987494eE17;
    address public constant TOKEN_dQUICK = 0x958d208Cdf087843e9AD98d23823d32E17d723A1;
    address public constant TOKEN_KNC = 0x1C954E8fe737F99f68Fa1CCda3e51ebDB291948C;

    // ERC21
    address public constant TOKEN_PM = 0xAA3e3709C79a133e56C17a7ded87802adF23083B;

    // Oracles
    address public constant ORACLE_CHAINLINK_USDCe_USD = 0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7;
    address public constant ORACLE_CHAINLINK_USDT_USD = 0x0A6513e40db6EB1b165753AD52E80663aeA50545;
    address public constant ORACLE_CHAINLINK_DAI_USD = 0x4746DeC9e833A82EC7C2C1356372CcF2cfcD2F3D;

    // AMMs
    address public constant POOL_UNISWAPV3_USDCe_USDT_100 = 0xDaC8A8E6DBf8c690ec6815e0fF03491B2770255D;
    address public constant POOL_UNISWAPV3_USDCe_DAI_100 = 0x5645dCB64c059aa11212707fbf4E7F984440a8Cf;
    address public constant POOL_UNISWAPV3_WMATIC_WETH_3000 = 0x167384319B41F7094e62f7506409Eb38079AbfF8;
    address public constant POOL_UNISWAPV3_WMATIC_WETH_500 = 0x86f1d8390222A3691C28938eC7404A1661E618e0;
    address public constant POOL_UNISWAPV3_WMATIC_USDCe_500 = 0xA374094527e1673A86dE625aa59517c5dE346d32;
    address public constant POOL_UNISWAPV3_WBTC_WETH_500 = 0x50eaEDB835021E4A108B7290636d62E9765cc6d7;
    address public constant POOL_UNISWAPV3_USDCe_WETH_500 = 0x45dDa9cb7c25131DF268515131f647d726f50608;
    address public constant POOL_UNISWAPV3_PROFIT_WETH_100 = 0xE5e70cb76446BEE0053b1EdF22CaDa861c80D51F;
    address public constant POOL_QUICKSWAPV3_USDCe_USDT = 0x7B925e617aefd7FB3a93Abe3a701135D7a1Ba710;
    address public constant POOL_QUICKSWAPV3_USDCe_DAI = 0xe7E0eB9F6bCcCfe847fDf62a3628319a092F11a2;
    address public constant POOL_QUICKSWAPV3_USDCe_WETH = 0x55CAaBB0d2b704FD0eF8192A7E35D8837e678207;
    address public constant POOL_QUICKSWAPV3_WMATIC_USDCe = 0xAE81FAc689A1b4b1e06e7ef4a2ab4CD8aC0A087D;
    address public constant POOL_QUICKSWAPV3_USDCe_QUICK = 0x022df0b3341B3A0157EEA97dD024A93f7496D631;
    address public constant POOL_QUICKSWAPV3_USDT_DAI = 0xefFA9E5e63ba18160Ee26BdA56b42F3368719615;
    address public constant POOL_QUICKSWAPV3_WBTC_WETH = 0xAC4494e30a85369e332BDB5230d6d694d4259DbC;
    address public constant POOL_QUICKSWAPV3_WBTC_USDCe = 0xA5CD8351Cbf30B531C7b11B0D9d3Ff38eA2E280f;
    address public constant POOL_QUICKSWAPV3_WMATIC_WETH = 0x479e1B71A702a595e19b6d5932CD5c863ab57ee0;
    address public constant POOL_QUICKSWAPV3_WMATIC_USDT = 0x5b41EEDCfC8e0AE47493d4945Aa1AE4fe05430ff;
    address public constant POOL_QUICKSWAPV3_WETH_USDT = 0x9CEff2F5138fC59eB925d270b8A7A9C02a1810f2;
    address public constant POOL_QUICKSWAPV3_dQUICK_QUICK = 0x194257104FabFd9f48bD01bd71A719637B4bbfA9;
    address public constant POOL_KYBER_USDCe_USDT = 0x879664ce5A919727b3Ed4035Cf12F7F740E8dF00;
    address public constant POOL_KYBER_USDCe_DAI = 0x02A3E4184b145eE64A6Df3c561A3C0c6e2f23DFa;
    address public constant POOL_KYBER_KNC_USDCe = 0x4B440a7DE0Ab7041934d0c171849A76CC33234Fa;

    // Gelato
    address public constant GELATO_AUTOMATE = 0x527a819db1eb0e34426297b03bae11F2f8B3A19E;

    // QuickSwap V3
    address public constant QUICKSWAP_POSITION_MANAGER = 0x8eF88E4c7CfbbaC1C163f7eddd4B578792201de6;
    address public constant QUICKSWAP_FARMING_CENTER = 0x7F281A8cdF66eF5e9db8434Ec6D97acc1bc01E78;

    // Gamma
    address public constant GAMMA_QUICKSWAP_MASTERCHEF = 0x20ec0d06F447d550fC6edee42121bc8C1817b97D;
    address public constant GAMMA_UNIPROXY = 0xe0A61107E250f8B5B24bf272baBFCf638569830C;
    address public constant GAMMA_UNIPROXY_2 = 0xA42d55074869491D60Ac05490376B74cF19B00e6;
    address public constant GAMMA_POS_DAI_USDT = 0x45A3A657b834699f5cC902e796c547F826703b79;
    address public constant GAMMA_POS_USDCe_USDT = 0x795f8c9B0A0Da9Cd8dea65Fc10f9B57AbC532E58;
    address public constant GAMMA_POS_USDCe_WETH_WIDE = 0x6077177d4c41E114780D9901C9b5c784841C523f;
    address public constant GAMMA_POS_WMATIC_WETH_NARROW = 0x02203f2351E7aC6aB5051205172D3f772db7D814;
    address public constant GAMMA_POS_WMATIC_WETH_WIDE = 0x81Cec323BF8C4164c66ec066F53cc053A535f03D;
    address public constant GAMMA_POS_WMATIC_USDT_NARROW = 0x598cA33b7F5FAB560ddC8E76D94A4b4AA52566d7;
    address public constant GAMMA_POS_WMATIC_USDT_WIDE = 0x9134f456D33d1288de26271730047AE0c5CB6F71;
    address public constant GAMMA_POS_WETH_USDT_NARROW = 0x5928f9f61902b139e1c40cBa59077516734ff09f;
    address public constant GAMMA_POS_WETH_USDT_WIDE = 0x3672d301778750C41a7864980A5ddbC2aF99476E;
    address public constant GAMMA_POS_WBTC_WETH_NARROW = 0x4B9e26a02121a1C541403a611b542965Bd4b68Ce;
    address public constant GAMMA_POS_WBTC_WETH_WIDE = 0xadc7B4096C3059Ec578585Df36E6E1286d345367;
    address public constant GAMMA_POS_WBTC_USDCe_NARROW = 0x3f35705479d9d77c619b2aAC9dd7a64e57151506;
    address public constant GAMMA_POS_WBTC_USDCe_WIDE = 0xE40a5aa22CBCcc8165aedd86f6d03fC5F551c3C6;
    address public constant GAMMA_POS_USDCe_WETH_NARROW = 0x3Cc20A6795c4b57d9817399F68E83e71C8626580;
    address public constant GAMMA_POS_WMATIC_USDCe_NARROW = 0x04d521E2c414E6d898c6F2599FdD863Edf49e247;
    address public constant GAMMA_POS_WMATIC_USDCe_WIDE = 0x4A83253e88e77E8d518638974530d0cBbbF3b675;

    // DeX aggregators
    address public constant ONE_INCH = 0x1111111254EEB25477B68fb85Ed929f73A960582;

    function runDeploy(bool showLog) internal returns (address platform) {
        //region ----- DeployPlatform -----
        uint[] memory buildingPrice = new uint[](3);
        buildingPrice[0] = 50_000e18;
        buildingPrice[1] = 50_000e18;
        buildingPrice[2] = 100_000e18;
        platform = DeployLib.deployPlatform(
            "23.12.2-alpha",
            MULTISIG,
            TOKEN_PM,
            TOKEN_SDIV,
            buildingPrice,
            "Polygon",
            CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x7746d7), bytes3(0x040206))),
            TOKEN_USDCe,
            GELATO_AUTOMATE,
            1e18,
            2e18
        );
        if (showLog) {
            console.log("Deployed Stability platform", IPlatform(platform).platformVersion());
            console.log("Platform address: ", platform);
        }
        //endregion -- DeployPlatform ----

        //region ----- DeployAndSetupOracleAdapters -----
        IPriceReader priceReader = PriceReader(IPlatform(platform).priceReader());
        // Chainlink
        {
            Proxy proxy = new Proxy();
            proxy.initProxy(address(new ChainlinkAdapter()));
            ChainlinkAdapter chainlinkAdapter = ChainlinkAdapter(address(proxy));
            chainlinkAdapter.initialize(platform);
            address[] memory assets = new address[](3);
            assets[0] = TOKEN_USDCe;
            assets[1] = TOKEN_USDT;
            assets[2] = TOKEN_DAI;
            address[] memory priceFeeds = new address[](3);
            priceFeeds[0] = ORACLE_CHAINLINK_USDCe_USD;
            priceFeeds[1] = ORACLE_CHAINLINK_USDT_USD;
            priceFeeds[2] = ORACLE_CHAINLINK_DAI_USD;
            chainlinkAdapter.addPriceFeeds(assets, priceFeeds);
            priceReader.addAdapter(address(chainlinkAdapter));
            DeployLib.logDeployAndSetupOracleAdapter("ChainLink", address(chainlinkAdapter), showLog);
        }
        //endregion -- DeployAndSetupOracleAdapters -----

        //region ----- Deploy AMM adapters -----
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.UNISWAPV3);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.ALGEBRA);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.KYBER);
        DeployLib.logDeployAmmAdapters(platform, showLog);
        //endregion -- Deploy AMM adapters ----

        //region ----- SetupSwapper -----
        (ISwapper.AddPoolData[] memory bcPools, ISwapper.AddPoolData[] memory pools) = routes();
        ISwapper swapper = ISwapper(IPlatform(platform).swapper());
        swapper.addBlueChipsPools(bcPools, false);
        swapper.addPools(pools, false);
        // todo auto thresholds
        address[] memory tokenIn = new address[](6);
        tokenIn[0] = TOKEN_USDCe;
        tokenIn[1] = TOKEN_USDT;
        tokenIn[2] = TOKEN_DAI;
        tokenIn[3] = TOKEN_WMATIC;
        tokenIn[4] = TOKEN_WETH;
        tokenIn[5] = TOKEN_dQUICK;
        uint[] memory thresholdAmount = new uint[](6);
        thresholdAmount[0] = 1e3;
        thresholdAmount[1] = 1e3;
        thresholdAmount[2] = 1e15;
        thresholdAmount[3] = 1e15;
        thresholdAmount[4] = 1e12;
        thresholdAmount[5] = 1e16; // 1 dQuick ~= $0.05
        swapper.setThresholds(tokenIn, thresholdAmount);
        DeployLib.logSetupSwapper(platform, showLog);
        //endregion -- SetupSwapper -----

        //region ----- Add farms -----
        IFactory.Farm[] memory _farms = farms();
        IFactory factory = IFactory(IPlatform(platform).factory());
        factory.addFarms(_farms);
        DeployLib.logAddedFarms(address(factory), showLog);
        //endregion -- Add farms -----

        //region ----- Reward tokens -----
        IPlatform(platform).setAllowedBBTokenVaults(TOKEN_PROFIT, 2);
        address[] memory allowedBoostRewardToken = new address[](2);
        address[] memory defaultBoostRewardToken = new address[](2);
        allowedBoostRewardToken[0] = TOKEN_PROFIT;
        allowedBoostRewardToken[1] = TOKEN_USDCe;
        defaultBoostRewardToken[0] = TOKEN_PROFIT;
        defaultBoostRewardToken[1] = TOKEN_USDCe;
        IPlatform(platform).addBoostTokens(allowedBoostRewardToken, defaultBoostRewardToken);
        DeployLib.logSetupRewardTokens(platform, showLog);
        //endregion -- Reward tokens -----

        //region ----- Deploy strategy logics -----
        DeployStrategyLib.deployStrategy(platform, StrategyIdLib.GAMMA_QUICKSWAP_FARM, true);
        DeployStrategyLib.deployStrategy(platform, StrategyIdLib.QUICKSWAPV3_STATIC_FARM, true);
        DeployLib.logDeployStrategies(platform, showLog);
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
        //region ----- BC pools ----
        bcPools = new ISwapper.AddPoolData[](5);
        bcPools[0] = ISwapper.AddPoolData({
            pool: POOL_UNISWAPV3_USDCe_USDT_100,
            ammAdapterId: AmmAdapterIdLib.UNISWAPV3,
            tokenIn: TOKEN_USDCe,
            tokenOut: TOKEN_USDT
        });
        bcPools[1] = ISwapper.AddPoolData({
            pool: POOL_UNISWAPV3_USDCe_DAI_100,
            ammAdapterId: AmmAdapterIdLib.UNISWAPV3,
            tokenIn: TOKEN_DAI,
            tokenOut: TOKEN_USDCe
        });
        bcPools[2] = ISwapper.AddPoolData({
            pool: POOL_UNISWAPV3_WMATIC_USDCe_500,
            ammAdapterId: AmmAdapterIdLib.UNISWAPV3,
            tokenIn: TOKEN_WMATIC,
            tokenOut: TOKEN_USDCe
        });
        bcPools[3] = ISwapper.AddPoolData({
            pool: POOL_UNISWAPV3_USDCe_WETH_500,
            ammAdapterId: AmmAdapterIdLib.UNISWAPV3,
            tokenIn: TOKEN_WETH,
            tokenOut: TOKEN_USDCe
        });
        bcPools[4] = ISwapper.AddPoolData({
            pool: POOL_UNISWAPV3_WBTC_WETH_500,
            ammAdapterId: AmmAdapterIdLib.UNISWAPV3,
            tokenIn: TOKEN_WBTC,
            tokenOut: TOKEN_WETH
        });
        //endregion -- BC pools ----

        //region ----- Pools ----
        pools = new ISwapper.AddPoolData[](10);
        uint i;
        // UniswapV3
        pools[i++] = ISwapper.AddPoolData({
            pool: POOL_UNISWAPV3_USDCe_USDT_100,
            ammAdapterId: AmmAdapterIdLib.UNISWAPV3,
            tokenIn: TOKEN_USDCe,
            tokenOut: TOKEN_USDT
        });
        pools[i++] = ISwapper.AddPoolData({
            pool: POOL_UNISWAPV3_USDCe_DAI_100,
            ammAdapterId: AmmAdapterIdLib.UNISWAPV3,
            tokenIn: TOKEN_DAI,
            tokenOut: TOKEN_USDCe
        });
        pools[i++] = ISwapper.AddPoolData({
            pool: POOL_UNISWAPV3_WMATIC_USDCe_500,
            ammAdapterId: AmmAdapterIdLib.UNISWAPV3,
            tokenIn: TOKEN_WMATIC,
            tokenOut: TOKEN_USDCe
        });
        pools[i++] = ISwapper.AddPoolData({
            pool: POOL_UNISWAPV3_USDCe_WETH_500,
            ammAdapterId: AmmAdapterIdLib.UNISWAPV3,
            tokenIn: TOKEN_WETH,
            tokenOut: TOKEN_USDCe
        });
        pools[i++] = ISwapper.AddPoolData({
            pool: POOL_UNISWAPV3_WBTC_WETH_500,
            ammAdapterId: AmmAdapterIdLib.UNISWAPV3,
            tokenIn: TOKEN_WBTC,
            tokenOut: TOKEN_WETH
        });
        pools[i++] = ISwapper.AddPoolData({
            pool: POOL_UNISWAPV3_PROFIT_WETH_100,
            ammAdapterId: AmmAdapterIdLib.UNISWAPV3,
            tokenIn: TOKEN_PROFIT,
            tokenOut: TOKEN_WETH
        });

        // QuickSwapV3
        pools[i++] = ISwapper.AddPoolData({
            pool: POOL_QUICKSWAPV3_USDT_DAI,
            ammAdapterId: AmmAdapterIdLib.ALGEBRA,
            tokenIn: TOKEN_USDT,
            tokenOut: TOKEN_DAI
        });
        pools[i++] = ISwapper.AddPoolData({
            pool: POOL_QUICKSWAPV3_USDCe_QUICK,
            ammAdapterId: AmmAdapterIdLib.ALGEBRA,
            tokenIn: TOKEN_QUICK,
            tokenOut: TOKEN_USDCe
        });
        pools[i++] = ISwapper.AddPoolData({
            pool: POOL_QUICKSWAPV3_dQUICK_QUICK,
            ammAdapterId: AmmAdapterIdLib.ALGEBRA,
            tokenIn: TOKEN_dQUICK,
            tokenOut: TOKEN_QUICK
        });

        // KyberSwap
        pools[i++] = ISwapper.AddPoolData({
            pool: POOL_KYBER_KNC_USDCe,
            ammAdapterId: AmmAdapterIdLib.KYBER,
            tokenIn: TOKEN_KNC,
            tokenOut: TOKEN_USDCe
        });
        //endregion -- Pools ----
    }

    function farms() public view returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](17);
        address[] memory rewardAssets;
        address[] memory addresses;
        uint[] memory nums;
        int24[] memory ticks;

        //region ----- QuickSwap V3 farms -----
        // [0] Earn dQUICK, WMATIC by static position in USDC/DAI pool on QuickSwap V3
        rewardAssets = new address[](2);
        rewardAssets[0] = TOKEN_dQUICK;
        rewardAssets[1] = TOKEN_WMATIC;
        addresses = new address[](2);
        addresses[0] = QUICKSWAP_POSITION_MANAGER;
        addresses[1] = QUICKSWAP_FARMING_CENTER;
        nums = new uint[](2);
        nums[0] = 1665192929;
        nums[1] = 4104559500;
        ticks = new int24[](2);
        ticks[0] = 276240;
        ticks[1] = 276420;
        _farms[0] = IFactory.Farm({
            status: 0,
            pool: POOL_QUICKSWAPV3_USDCe_DAI,
            strategyLogicId: StrategyIdLib.QUICKSWAPV3_STATIC_FARM,
            rewardAssets: rewardAssets,
            addresses: addresses,
            nums: nums,
            ticks: ticks
        });
        //endregion -- QuickSwap V3 farms -----

        //region ----- Gamma QuickSwap farms -----
        _farms[1] = _makeGammaQuickSwapFarm(
            TOKEN_dQUICK, address(0), GAMMA_POS_DAI_USDT, GAMMA_UNIPROXY, 55, uint(GammaLib.Presets.STABLE)
        );
        _farms[2] = _makeGammaQuickSwapFarm(
            TOKEN_dQUICK, TOKEN_WMATIC, GAMMA_POS_USDCe_USDT, GAMMA_UNIPROXY_2, 11, uint(GammaLib.Presets.STABLE)
        );
        _farms[3] = _makeGammaQuickSwapFarm(
            TOKEN_dQUICK, address(0), GAMMA_POS_WMATIC_WETH_NARROW, GAMMA_UNIPROXY_2, 0, uint(GammaLib.Presets.NARROW)
        );
        _farms[4] = _makeGammaQuickSwapFarm(
            TOKEN_dQUICK, address(0), GAMMA_POS_WBTC_WETH_NARROW, GAMMA_UNIPROXY_2, 8, uint(GammaLib.Presets.NARROW)
        );
        _farms[5] = _makeGammaQuickSwapFarm(
            TOKEN_dQUICK, TOKEN_WMATIC, GAMMA_POS_USDCe_WETH_NARROW, GAMMA_UNIPROXY_2, 4, uint(GammaLib.Presets.NARROW)
        );
        _farms[6] = _makeGammaQuickSwapFarm(
            TOKEN_dQUICK, TOKEN_WMATIC, GAMMA_POS_WMATIC_USDCe_NARROW, GAMMA_UNIPROXY_2, 2, uint(GammaLib.Presets.NARROW)
        );
        _farms[7] = _makeGammaQuickSwapFarm(
            TOKEN_dQUICK, address(0), GAMMA_POS_WMATIC_WETH_WIDE, GAMMA_UNIPROXY_2, 1, uint(GammaLib.Presets.WIDE)
        );
        _farms[8] = _makeGammaQuickSwapFarm(
            TOKEN_dQUICK, address(0), GAMMA_POS_WBTC_USDCe_NARROW, GAMMA_UNIPROXY_2, 6, uint(GammaLib.Presets.NARROW)
        );
        _farms[9] = _makeGammaQuickSwapFarm(
            TOKEN_dQUICK, address(0), GAMMA_POS_WMATIC_USDT_NARROW, GAMMA_UNIPROXY_2, 16, uint(GammaLib.Presets.NARROW)
        );
        _farms[10] = _makeGammaQuickSwapFarm(
            TOKEN_dQUICK, TOKEN_WMATIC, GAMMA_POS_USDCe_WETH_WIDE, GAMMA_UNIPROXY_2, 5, uint(GammaLib.Presets.WIDE)
        );
        _farms[11] = _makeGammaQuickSwapFarm(
            TOKEN_dQUICK, address(0), GAMMA_POS_WBTC_WETH_WIDE, GAMMA_UNIPROXY_2, 9, uint(GammaLib.Presets.WIDE)
        );
        _farms[12] = _makeGammaQuickSwapFarm(
            TOKEN_dQUICK, TOKEN_dQUICK, GAMMA_POS_WETH_USDT_NARROW, GAMMA_UNIPROXY_2, 26, uint(GammaLib.Presets.NARROW)
        );
        _farms[13] = _makeGammaQuickSwapFarm(
            TOKEN_dQUICK, TOKEN_WMATIC, GAMMA_POS_WMATIC_USDCe_WIDE, GAMMA_UNIPROXY_2, 3, uint(GammaLib.Presets.WIDE)
        );
        _farms[14] = _makeGammaQuickSwapFarm(
            TOKEN_dQUICK, address(0), GAMMA_POS_WBTC_USDCe_WIDE, GAMMA_UNIPROXY_2, 7, uint(GammaLib.Presets.WIDE)
        );
        _farms[15] = _makeGammaQuickSwapFarm(
            TOKEN_dQUICK, TOKEN_dQUICK, GAMMA_POS_WETH_USDT_WIDE, GAMMA_UNIPROXY_2, 27, uint(GammaLib.Presets.WIDE)
        );
        _farms[16] = _makeGammaQuickSwapFarm(
            TOKEN_dQUICK, address(0), GAMMA_POS_WMATIC_USDT_WIDE, GAMMA_UNIPROXY_2, 17, uint(GammaLib.Presets.WIDE)
        );
        //endregion --  Gamma QuickSwap farms -----
    }

    function _makeGammaQuickSwapFarm(
        address rewardAsset0,
        address rewardAsset1,
        address hypervisor,
        address uniProxy,
        uint pid,
        uint preset
    ) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IHypervisor(hypervisor).pool();
        farm.strategyLogicId = StrategyIdLib.GAMMA_QUICKSWAP_FARM;
        if (rewardAsset1 == address(0)) {
            farm.rewardAssets = new address[](1);
            farm.rewardAssets[0] = rewardAsset0;
        } else {
            farm.rewardAssets = new address[](2);
            farm.rewardAssets[0] = rewardAsset0;
            farm.rewardAssets[1] = rewardAsset1;
        }
        farm.addresses = new address[](3);
        farm.addresses[0] = uniProxy;
        farm.addresses[1] = GAMMA_QUICKSWAP_MASTERCHEF;
        farm.addresses[2] = hypervisor;
        farm.nums = new uint[](2);
        farm.nums[0] = pid;
        farm.nums[1] = preset;
        farm.ticks = new int24[](0);
        return farm;
    }

    function testPolygonLib() external {}
}
