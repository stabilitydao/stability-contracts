// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../src/core/proxy/Proxy.sol";
import "../src/adapters/libs/AmmAdapterIdLib.sol";
import "../src/adapters/ChainlinkAdapter.sol";
import "../src/strategies/libs/StrategyIdLib.sol";
import "../src/strategies/libs/ALMPositionNameLib.sol";
import "../src/interfaces/IFactory.sol";
import "../src/interfaces/IPlatform.sol";
import "../src/interfaces/ISwapper.sol";
import "../src/integrations/convex/IConvexRewardPool.sol";
import "../script/libs/DeployLib.sol";
import "../script/libs/DeployAdapterLib.sol";
import "../script/libs/DeployStrategyLib.sol";

/// @dev Addresses, routes, farms, strategy logics, reward tokens, deploy function and other data for Polygon network
library PolygonLib {
    // initial addresses
    address public constant MULTISIG =
        0x36780E69D38c8b175761c6C5F8eD42E61ee490E9; // team

    // ERC20
    address public constant TOKEN_PROFIT =
        0x48469a0481254d5945E7E56c1Eb9861429c02f44;
    address public constant TOKEN_SDIV =
        0x9844a1c30462B55cd383A2C06f90BB4171f9D4bB;
    address public constant TOKEN_USDCe =
        0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    address public constant TOKEN_WETH =
        0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address public constant TOKEN_WMATIC =
        0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public constant TOKEN_USDT =
        0xc2132D05D31c914a87C6611C10748AEb04B58e8F;
    address public constant TOKEN_DAI =
        0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
    address public constant TOKEN_WBTC =
        0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6;
    address public constant TOKEN_QUICK =
        0xB5C064F955D8e7F38fE0460C556a72987494eE17;
    address public constant TOKEN_dQUICK =
        0x958d208Cdf087843e9AD98d23823d32E17d723A1;
    address public constant TOKEN_KNC =
        0x1C954E8fe737F99f68Fa1CCda3e51ebDB291948C;
    address public constant TOKEN_USDC =
        0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359;
    address public constant TOKEN_COMP =
        0x8505b9d2254A7Ae468c0E9dd10Ccea3A837aef5c;
    address public constant TOKEN_ICHI =
        0x111111517e4929D3dcbdfa7CCe55d30d4B6BC4d6;
    address public constant TOKEN_RETRO =
        0xBFA35599c7AEbb0dAcE9b5aa3ca5f2a79624D8Eb;
    address public constant TOKEN_oRETRO =
        0x3A29CAb2E124919d14a6F735b6033a3AaD2B260F;
    address public constant TOKEN_CASH =
        0x5D066D022EDE10eFa2717eD3D79f22F949F8C175;
    address public constant TOKEN_crvUSD =
        0xc4Ce1D6F5D98D65eE25Cf85e9F2E9DcFEe6Cb5d6;
    address public constant TOKEN_CRV =
        0x172370d5Cd63279eFa6d502DAB29171933a610AF;

    // ERC21
    address public constant TOKEN_PM =
        0xAA3e3709C79a133e56C17a7ded87802adF23083B;

    // Oracles
    address public constant ORACLE_CHAINLINK_USDCe_USD =
        0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7;
    address public constant ORACLE_CHAINLINK_USDT_USD =
        0x0A6513e40db6EB1b165753AD52E80663aeA50545;
    address public constant ORACLE_CHAINLINK_DAI_USD =
        0x4746DeC9e833A82EC7C2C1356372CcF2cfcD2F3D;

    // AMMs
    address public constant POOL_UNISWAPV3_USDCe_USDT_100 =
        0xDaC8A8E6DBf8c690ec6815e0fF03491B2770255D;
    address public constant POOL_UNISWAPV3_USDCe_DAI_100 =
        0x5645dCB64c059aa11212707fbf4E7F984440a8Cf;
    address public constant POOL_UNISWAPV3_WMATIC_WETH_3000 =
        0x167384319B41F7094e62f7506409Eb38079AbfF8;
    address public constant POOL_UNISWAPV3_WMATIC_WETH_500 =
        0x86f1d8390222A3691C28938eC7404A1661E618e0;
    address public constant POOL_UNISWAPV3_WMATIC_USDCe_500 =
        0xA374094527e1673A86dE625aa59517c5dE346d32;
    address public constant POOL_UNISWAPV3_WBTC_WETH_500 =
        0x50eaEDB835021E4A108B7290636d62E9765cc6d7;
    address public constant POOL_UNISWAPV3_USDCe_WETH_500 =
        0x45dDa9cb7c25131DF268515131f647d726f50608;
    address public constant POOL_UNISWAPV3_PROFIT_WETH_100 =
        0xE5e70cb76446BEE0053b1EdF22CaDa861c80D51F;
    address public constant POOL_UNISWAPV3_WETH_COMP_3000 =
        0x2260E0081A2A042DC55A07D379eb3c18bE28A1F2;
    address public constant POOL_UNISWAPV3_WMATIC_COMP_3000 =
        0x495b3576e2f67fa870e14d0996433FbdB4015794;
    address public constant POOL_QUICKSWAPV3_USDCe_USDT =
        0x7B925e617aefd7FB3a93Abe3a701135D7a1Ba710;
    address public constant POOL_QUICKSWAPV3_USDCe_DAI =
        0xe7E0eB9F6bCcCfe847fDf62a3628319a092F11a2;
    address public constant POOL_QUICKSWAPV3_USDCe_WETH =
        0x55CAaBB0d2b704FD0eF8192A7E35D8837e678207;
    address public constant POOL_QUICKSWAPV3_WMATIC_USDCe =
        0xAE81FAc689A1b4b1e06e7ef4a2ab4CD8aC0A087D;
    address public constant POOL_QUICKSWAPV3_USDCe_QUICK =
        0x022df0b3341B3A0157EEA97dD024A93f7496D631;
    address public constant POOL_QUICKSWAPV3_USDT_DAI =
        0xefFA9E5e63ba18160Ee26BdA56b42F3368719615;
    address public constant POOL_QUICKSWAPV3_WBTC_WETH =
        0xAC4494e30a85369e332BDB5230d6d694d4259DbC;
    address public constant POOL_QUICKSWAPV3_WBTC_USDCe =
        0xA5CD8351Cbf30B531C7b11B0D9d3Ff38eA2E280f;
    address public constant POOL_QUICKSWAPV3_WMATIC_WETH =
        0x479e1B71A702a595e19b6d5932CD5c863ab57ee0;
    address public constant POOL_QUICKSWAPV3_WMATIC_USDT =
        0x5b41EEDCfC8e0AE47493d4945Aa1AE4fe05430ff;
    address public constant POOL_QUICKSWAPV3_WETH_USDT =
        0x9CEff2F5138fC59eB925d270b8A7A9C02a1810f2;
    address public constant POOL_QUICKSWAPV3_dQUICK_QUICK =
        0x194257104FabFd9f48bD01bd71A719637B4bbfA9;
    address public constant POOL_QUICKSWAPV3_USDCe_USDC =
        0xEecB5Db986c20a8C88D8332E7e252A9671565751;
    address public constant POOL_QUICKSWAPV3_USDC_WETH =
        0xa6AeDF7c4Ed6e821E67a6BfD56FD1702aD9a9719;
    address public constant POOL_QUICKSWAPV3_WMATIC_USDC =
        0x6669B4706cC152F359e947BCa68E263A87c52634;
    address public constant POOL_QUICKSWAPV3_USDC_DAI =
        0xBC8f3da0bd42E1F2509cd8671Ce7c7E5f7fd39c8;
    address public constant POOL_QUICKSWAPV3_CRV_WMATIC =
        0x00A6177C6455A29B8dAa7144B2bEfc9F2147BB7E;
    address public constant POOL_KYBER_USDCe_USDT =
        0x879664ce5A919727b3Ed4035Cf12F7F740E8dF00;
    address public constant POOL_KYBER_USDCe_DAI =
        0x02A3E4184b145eE64A6Df3c561A3C0c6e2f23DFa;
    address public constant POOL_KYBER_KNC_USDCe =
        0x4B440a7DE0Ab7041934d0c171849A76CC33234Fa;
    address public constant POOL_UNISWAPV3_ICHI_WMATIC_100 =
        0x3D86A4B8C1b55509792d57e0C038128cC9C14fE7;
    address public constant POOL_RETRO_WMATIC_WETH_500 =
        0x1a34EaBbe928Bf431B679959379b2225d60D9cdA;
    address public constant POOL_RETRO_oRETRO_RETRO_10000 =
        0x387FBcE5E2933Bd3a7243D0be2aAC8fD9Ab3D55d;
    address public constant POOL_RETRO_USDCe_RETRO_10000 =
        0xc7d8B9c270D0E31A6a0Cf4496fe019766Be42E15;
    address public constant POOL_RETRO_WMATIC_USDCe_500 =
        0xEC15624FBB314eb05BaaD4cA49b7904C0Cb6b645;
    address public constant POOL_RETRO_WBTC_WETH_500 =
        0xb694E3bdd4BCdF843510983D257679D1E627C474;
    address public constant POOL_RETRO_USDCe_CASH_100 =
        0x619259F699839dD1498FFC22297044462483bD27;
    address public constant POOL_RETRO_CASH_RETRO_10000 =
        0xb47A07966cE6812702C0567d03725F1b37E27877;
    address public constant POOL_CURVE_crvUSD_USDCe =
        0x864490Cf55dc2Dee3f0ca4D06F5f80b2BB154a03;
    address public constant POOL_CURVE_crvUSD_USDT =
        0xA70Af99bFF6b168327f9D1480e29173e757c7904;
    address public constant POOL_CURVE_crvUSD_DAI =
        0x62c949ee985b125Ff2d7ddcf4Fe7AEcB0a040E2a;
    address public constant POOL_CURVE_crvUSD_USDC =
        0x5225010A0AE133B357861782B0B865a48471b2C5;

    // Gelato
    address public constant GELATO_AUTOMATE =
        0x527a819db1eb0e34426297b03bae11F2f8B3A19E;

    // QuickSwap V3
    address public constant QUICKSWAP_POSITION_MANAGER =
        0x8eF88E4c7CfbbaC1C163f7eddd4B578792201de6;

    // Gamma
    address public constant GAMMA_QUICKSWAP_UNIPROXY =
        0xA42d55074869491D60Ac05490376B74cF19B00e6;
    address public constant GAMMA_QUICKSWAP_USDCe_USDT =
        0x795f8c9B0A0Da9Cd8dea65Fc10f9B57AbC532E58;
    address public constant GAMMA_QUICKSWAP_USDCe_WETH_WIDE =
        0x6077177d4c41E114780D9901C9b5c784841C523f;
    address public constant GAMMA_QUICKSWAP_WMATIC_WETH_NARROW =
        0x02203f2351E7aC6aB5051205172D3f772db7D814;
    address public constant GAMMA_QUICKSWAP_WMATIC_WETH_WIDE =
        0x81Cec323BF8C4164c66ec066F53cc053A535f03D;
    address public constant GAMMA_QUICKSWAP_WMATIC_USDT_NARROW =
        0x598cA33b7F5FAB560ddC8E76D94A4b4AA52566d7;
    address public constant GAMMA_QUICKSWAP_WMATIC_USDT_WIDE =
        0x9134f456D33d1288de26271730047AE0c5CB6F71;
    address public constant GAMMA_QUICKSWAP_WETH_USDT_NARROW =
        0x5928f9f61902b139e1c40cBa59077516734ff09f;
    address public constant GAMMA_QUICKSWAP_WETH_USDT_WIDE =
        0x3672d301778750C41a7864980A5ddbC2aF99476E;
    address public constant GAMMA_QUICKSWAP_WBTC_WETH_NARROW =
        0x4B9e26a02121a1C541403a611b542965Bd4b68Ce;
    address public constant GAMMA_QUICKSWAP_WBTC_WETH_WIDE =
        0xadc7B4096C3059Ec578585Df36E6E1286d345367;
    address public constant GAMMA_QUICKSWAP_WBTC_USDCe_NARROW =
        0x3f35705479d9d77c619b2aAC9dd7a64e57151506;
    address public constant GAMMA_QUICKSWAP_WBTC_USDCe_WIDE =
        0xE40a5aa22CBCcc8165aedd86f6d03fC5F551c3C6;
    address public constant GAMMA_QUICKSWAP_USDCe_WETH_NARROW =
        0x3Cc20A6795c4b57d9817399F68E83e71C8626580;
    address public constant GAMMA_QUICKSWAP_WMATIC_USDCe_NARROW =
        0x04d521E2c414E6d898c6F2599FdD863Edf49e247;
    address public constant GAMMA_QUICKSWAP_WMATIC_USDCe_WIDE =
        0x4A83253e88e77E8d518638974530d0cBbbF3b675;
    address public constant GAMMA_QUICKSWAP_USDC_WETH_NARROW =
        0x3974FbDC22741A1632E024192111107b202F214f;
    address public constant GAMMA_QUICKSWAP_WMATIC_USDC_NARROW =
        0x1cf4293125913cB3Dea4aD7f2bb4795B9e896CE9;
    address public constant GAMMA_RETRO_UNIPROXY =
        0xDC8eE75f52FABF057ae43Bb4B85C55315b57186c;
    address public constant GAMMA_RETRO_WMATIC_USDCe_NARROW =
        0xBE4E30b74b558E41f5837dC86562DF44aF57A013;
    address public constant GAMMA_RETRO_WMATIC_WETH_NARROW =
        0xe7806B5ba13d4B2Ab3EaB3061cB31d4a4F3390Aa;
    address public constant GAMMA_RETRO_WBTC_WETH_WIDE =
        0x336536F5bB478D8624dDcE0942fdeF5C92bC4662;

    // Compound
    address public constant COMPOUND_COMET =
        0xF25212E676D1F7F89Cd72fFEe66158f541246445;
    address public constant COMPOUND_COMET_REWARDS =
        0x45939657d1CA34A8FA39A924B71D28Fe8431e581;

    // DefiEdge
    address public constant DEFIEDGE_STRATEGY_WMATIC_WETH_NARROW_1 =
        0xd778C83E7cA19c2217d98daDACf7fD03B79B18cB;
    address public constant DEFIEDGE_STRATEGY_WMATIC_WETH_NARROW_2 =
        0x07d82761C3527Caf190b946e13d5C11291194aE6;
    address public constant DEFIEDGE_STRATEGY_WMATIC_USDC_NARROW =
        0x29f177EFF806b8A71Ff8C7259eC359312CaCE22D;

    // Steer
    address public constant STEER_STRATEGY_WMATIC_USDC =
        0x280bE4533891E887F55847A773B93d043984Fbd5;
    address public constant STEER_STRATEGY_WBTC_WETH =
        0x12a7b5510f8f5E13F75aFF4d00b2F88CC99d22DB;

    // Ichi
    address public constant ICHI_QUICKSWAP_WMATIC_USDT =
        0x5D73D117Ffb8AD26e6CC9f2621d52f479AAA8C5B;
    address public constant ICHI_QUICKSWAP_WBTC_WETH =
        0x5D1b077212b624fe580a84384Ffea44da752ccb3;
    address public constant ICHI_QUICKSWAP_WETH_USDT =
        0xc46FAb3Af8aA7A56feDa351a22B56749dA313473;
    address public constant ICHI_RETRO_WMATIC_WETH_MATIC =
        0x38F41FDe5cABC569E808537FdaF390cD7f0dC0f6;
    address public constant ICHI_RETRO_WMATIC_WETH_ETH =
        0xE9BD439259DE0347DC26B86b3E73437E93858283;
    address public constant ICHI_RETRO_WMATIC_USDCe_MATIC =
        0x91f935892355C8CA4468C44D2c4bAE1A23c60c14;
    address public constant ICHI_RETRO_WMATIC_USDCe_USDC =
        0x5Ef5630195164956d394fF8093C1B6964cb5814B;
    address public constant ICHI_RETRO_WBTC_WETH_ETH =
        0x0B0302014DD4FB6A77da03bF9034db5FEcB68eA8;

    // DeX aggregators
    address public constant ONE_INCH =
        0x1111111254EEB25477B68fb85Ed929f73A960582;

    // Retro
    address public constant RETRO_QUOTER =
        0xddc9Ef56c6bf83F7116Fad5Fbc41272B07ac70C1;

    // Convex
    address public constant CONVEX_BOOSTER =
        0xddc9Ef56c6bf83F7116Fad5Fbc41272B07ac70C1;
    address public constant CONVEX_REWARD_POOL_crvUSD_USDCe =
        0xBFEE9F3E015adC754066424AEd535313dc764116;
    address public constant CONVEX_REWARD_POOL_crvUSD_USDT =
        0xd2D8BEB901f90163bE4667A85cDDEbB7177eb3E3;
    address public constant CONVEX_REWARD_POOL_crvUSD_DAI =
        0xaCb744c7e7C95586DB83Eda3209e6483Fb1FCbA4;
    address public constant CONVEX_REWARD_POOL_crvUSD_USDC =
        0x11F2217fa1D5c44Eae310b9b985E2964FC47D8f9;

    // Yearn V3
    address public constant YEARN_DAI =
        0x90b2f54C6aDDAD41b8f6c4fCCd555197BC0F773B;
    address public constant YEARN_USDT =
        0xBb287E6017d3DEb0e2E65061e8684eab21060123;
    address public constant YEARN_USDCe =
        0xA013Fbd4b711f9ded6fB09C1c0d358E2FbC2EAA0;
    address public constant YEARN_WMATIC =
        0x28F53bA70E5c8ce8D03b1FaD41E9dF11Bb646c36;
    address public constant YEARN_WETH =
        0x305F25377d0a39091e99B975558b1bdfC3975654;

    function runDeploy(bool showLog) internal returns (address platform) {
        //region ----- DeployPlatform -----
        uint[] memory buildingPrice = new uint[](3);
        buildingPrice[0] = 50_000e18;
        buildingPrice[1] = 50_000e18;
        buildingPrice[2] = 100_000e18;
        platform = DeployLib.deployPlatform(
            "24.05.0-alpha",
            MULTISIG,
            TOKEN_PM,
            TOKEN_SDIV,
            buildingPrice,
            "Polygon",
            CommonLib.bytesToBytes32(
                abi.encodePacked(bytes3(0x7746d7), bytes3(0x040206))
            ),
            TOKEN_USDCe,
            GELATO_AUTOMATE,
            1e18,
            2e18
        );
        if (showLog) {
            console.log(
                "Deployed Stability platform",
                IPlatform(platform).platformVersion()
            );
            console.log("Platform address: ", platform);
        }
        //endregion -- DeployPlatform ----

        //region ----- DeployAndSetupOracleAdapters -----
        IPriceReader priceReader = PriceReader(
            IPlatform(platform).priceReader()
        );
        // Chainlink
        {
            Proxy proxy = new Proxy();
            proxy.initProxy(address(new ChainlinkAdapter()));
            ChainlinkAdapter chainlinkAdapter = ChainlinkAdapter(
                address(proxy)
            );
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
            DeployLib.logDeployAndSetupOracleAdapter(
                "ChainLink",
                address(chainlinkAdapter),
                showLog
            );
        }
        //endregion -- DeployAndSetupOracleAdapters -----

        //region ----- Deploy AMM adapters -----
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.UNISWAPV3);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.ALGEBRA);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.KYBER);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.CURVE);
        DeployLib.logDeployAmmAdapters(platform, showLog);
        //endregion -- Deploy AMM adapters ----

        //region ----- SetupSwapper -----
        {
            (
                ISwapper.AddPoolData[] memory bcPools,
                ISwapper.AddPoolData[] memory pools
            ) = routes();
            ISwapper.AddPoolData[] memory pools2 = routes2();
            ISwapper swapper = ISwapper(IPlatform(platform).swapper());
            swapper.addBlueChipsPools(bcPools, false);
            swapper.addPools(pools, false);
            swapper.addPools(pools2, false);
            // todo auto thresholds
            address[] memory tokenIn = new address[](10);
            tokenIn[0] = TOKEN_USDCe;
            tokenIn[1] = TOKEN_USDT;
            tokenIn[2] = TOKEN_DAI;
            tokenIn[3] = TOKEN_WMATIC;
            tokenIn[4] = TOKEN_WETH;
            tokenIn[5] = TOKEN_dQUICK;
            tokenIn[6] = TOKEN_USDC;
            tokenIn[7] = TOKEN_COMP;
            tokenIn[8] = TOKEN_CRV;
            tokenIn[9] = TOKEN_crvUSD;
            uint[] memory thresholdAmount = new uint[](10);
            thresholdAmount[0] = 1e3;
            thresholdAmount[1] = 1e3;
            thresholdAmount[2] = 1e15;
            thresholdAmount[3] = 1e15;
            thresholdAmount[4] = 1e12;
            thresholdAmount[5] = 1e16; // 1 dQuick ~= $0.05
            thresholdAmount[6] = 1e3;
            thresholdAmount[7] = 1e15;
            thresholdAmount[8] = 1e15;
            thresholdAmount[9] = 1e15;
            swapper.setThresholds(tokenIn, thresholdAmount);
            DeployLib.logSetupSwapper(platform, showLog);
        }
        //endregion -- SetupSwapper -----

        //region ----- Add farms -----
        IFactory factory = IFactory(IPlatform(platform).factory());
        factory.addFarms(farms());
        factory.addFarms(farms2());
        factory.addFarms(farms3());
        factory.addFarms(farms4());
        factory.addFarms(farms5());
        factory.addFarms(farms6());
        if (block.number > 54573098) {
            // Mar-12-2024 02:41:42 PM +UTC
            factory.addFarms(farms7());
            factory.addFarms(farms8());
        }
        DeployLib.logAddedFarms(address(factory), showLog);
        //endregion -- Add farms -----

        //region ----- Add strategy available init params -----
        IFactory.StrategyAvailableInitParams memory p;
        p.initAddresses = new address[](5);
        p.initAddresses[0] = YEARN_USDCe;
        p.initAddresses[1] = YEARN_USDT;
        p.initAddresses[2] = YEARN_DAI;
        p.initAddresses[3] = YEARN_WETH;
        p.initAddresses[4] = YEARN_WMATIC;
        p.initNums = new uint[](0);
        p.initTicks = new int24[](0);
        factory.setStrategyAvailableInitParams(StrategyIdLib.YEARN, p);
        //endregion -- Add strategy available init params -----

        //region ----- Reward tokens -----
        IPlatform(platform).setAllowedBBTokenVaults(TOKEN_PROFIT, 2);
        address[] memory allowedBoostRewardToken = new address[](2);
        address[] memory defaultBoostRewardToken = new address[](2);
        allowedBoostRewardToken[0] = TOKEN_PROFIT;
        allowedBoostRewardToken[1] = TOKEN_USDCe;
        defaultBoostRewardToken[0] = TOKEN_PROFIT;
        defaultBoostRewardToken[1] = TOKEN_USDCe;
        IPlatform(platform).addBoostTokens(
            allowedBoostRewardToken,
            defaultBoostRewardToken
        );
        DeployLib.logSetupRewardTokens(platform, showLog);
        //endregion -- Reward tokens -----

        //region ----- Deploy strategy logics -----
        DeployStrategyLib.deployStrategy(
            platform,
            StrategyIdLib.GAMMA_QUICKSWAP_MERKL_FARM,
            true
        );
        DeployStrategyLib.deployStrategy(
            platform,
            StrategyIdLib.QUICKSWAP_STATIC_MERKL_FARM,
            true
        );
        DeployStrategyLib.deployStrategy(
            platform,
            StrategyIdLib.COMPOUND_FARM,
            true
        );
        DeployStrategyLib.deployStrategy(
            platform,
            StrategyIdLib.DEFIEDGE_QUICKSWAP_MERKL_FARM,
            true
        );
        DeployStrategyLib.deployStrategy(
            platform,
            StrategyIdLib.ICHI_QUICKSWAP_MERKL_FARM,
            true
        );
        DeployStrategyLib.deployStrategy(
            platform,
            StrategyIdLib.ICHI_RETRO_MERKL_FARM,
            true
        );
        DeployStrategyLib.deployStrategy(
            platform,
            StrategyIdLib.GAMMA_RETRO_MERKL_FARM,
            true
        );
        DeployStrategyLib.deployStrategy(
            platform,
            StrategyIdLib.STEER_QUICKSWAP_MERKL_FARM,
            true
        );
        DeployStrategyLib.deployStrategy(
            platform,
            StrategyIdLib.CURVE_CONVEX_FARM,
            true
        );
        DeployStrategyLib.deployStrategy(platform, StrategyIdLib.YEARN, false);
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
        returns (
            ISwapper.AddPoolData[] memory bcPools,
            ISwapper.AddPoolData[] memory pools
        )
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

    function routes2()
        public
        pure
        returns (ISwapper.AddPoolData[] memory pools)
    {
        pools = new ISwapper.AddPoolData[](8);
        uint i;
        // New routes jan-2024
        pools[i++] = ISwapper.AddPoolData({
            pool: POOL_QUICKSWAPV3_USDCe_USDC,
            ammAdapterId: AmmAdapterIdLib.ALGEBRA,
            tokenIn: TOKEN_USDC,
            tokenOut: TOKEN_USDCe
        });
        pools[i++] = ISwapper.AddPoolData({
            pool: POOL_UNISWAPV3_WETH_COMP_3000,
            ammAdapterId: AmmAdapterIdLib.UNISWAPV3,
            tokenIn: TOKEN_COMP,
            tokenOut: TOKEN_WETH
        });
        pools[i++] = ISwapper.AddPoolData({
            pool: POOL_UNISWAPV3_ICHI_WMATIC_100,
            ammAdapterId: AmmAdapterIdLib.UNISWAPV3,
            tokenIn: TOKEN_ICHI,
            tokenOut: TOKEN_WMATIC
        });
        // routes for RETRO strategies
        pools[i++] = ISwapper.AddPoolData({
            pool: POOL_RETRO_USDCe_RETRO_10000,
            ammAdapterId: AmmAdapterIdLib.UNISWAPV3,
            tokenIn: TOKEN_RETRO,
            tokenOut: TOKEN_USDCe
        });
        pools[i++] = ISwapper.AddPoolData({
            pool: POOL_RETRO_oRETRO_RETRO_10000,
            ammAdapterId: AmmAdapterIdLib.UNISWAPV3,
            tokenIn: TOKEN_oRETRO,
            tokenOut: TOKEN_RETRO
        });
        pools[i++] = ISwapper.AddPoolData({
            pool: POOL_RETRO_USDCe_CASH_100,
            ammAdapterId: AmmAdapterIdLib.UNISWAPV3,
            tokenIn: TOKEN_CASH,
            tokenOut: TOKEN_USDCe
        });
        // crvUSD
        pools[i++] = ISwapper.AddPoolData({
            pool: POOL_CURVE_crvUSD_USDCe,
            ammAdapterId: AmmAdapterIdLib.CURVE,
            tokenIn: TOKEN_crvUSD,
            tokenOut: TOKEN_USDCe
        });
        pools[i++] = ISwapper.AddPoolData({
            pool: POOL_QUICKSWAPV3_CRV_WMATIC,
            ammAdapterId: AmmAdapterIdLib.ALGEBRA,
            tokenIn: TOKEN_CRV,
            tokenOut: TOKEN_WMATIC
        });
        // Steer WMATIC/USDC
        pools[i++] = ISwapper.AddPoolData({
            pool: POOL_QUICKSWAPV3_WMATIC_USDC,
            ammAdapterId: AmmAdapterIdLib.ALGEBRA,
            tokenIn: TOKEN_WMATIC,
            tokenOut: TOKEN_USDC
        });
    }

    function farms() public view returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](16);
        address[] memory rewardAssets;
        address[] memory addresses;
        uint[] memory nums;
        int24[] memory ticks;
        uint i;

        //region ----- QuickSwap V3 farms -----
        // [0] Earn dQUICK, WMATIC by static position in USDC/DAI pool on QuickSwap V3
        rewardAssets = new address[](2);
        rewardAssets[0] = TOKEN_dQUICK;
        rewardAssets[1] = TOKEN_WMATIC;
        addresses = new address[](1);
        addresses[0] = QUICKSWAP_POSITION_MANAGER;
        nums = new uint[](0);
        ticks = new int24[](2);
        ticks[0] = 276240;
        ticks[1] = 276420;

        _farms[i++] = IFactory.Farm({
            status: 0,
            pool: POOL_QUICKSWAPV3_USDCe_DAI,
            strategyLogicId: StrategyIdLib.QUICKSWAP_STATIC_MERKL_FARM,
            rewardAssets: rewardAssets,
            addresses: addresses,
            nums: nums,
            ticks: ticks
        });
        //endregion -- QuickSwap V3 farms -----

        //region ----- Gamma QuickSwap Merkl farms -----
        _farms[i++] = _makeGammaQuickSwapMerklFarm(
            GAMMA_QUICKSWAP_USDCe_USDT,
            ALMPositionNameLib.STABLE
        );
        _farms[i++] = _makeGammaQuickSwapMerklFarm(
            GAMMA_QUICKSWAP_WMATIC_WETH_NARROW,
            ALMPositionNameLib.NARROW
        );
        _farms[i++] = _makeGammaQuickSwapMerklFarm(
            GAMMA_QUICKSWAP_WBTC_WETH_NARROW,
            ALMPositionNameLib.NARROW
        );
        _farms[i++] = _makeGammaQuickSwapMerklFarm(
            GAMMA_QUICKSWAP_USDCe_WETH_NARROW,
            ALMPositionNameLib.NARROW
        );
        _farms[i++] = _makeGammaQuickSwapMerklFarm(
            GAMMA_QUICKSWAP_WMATIC_USDCe_NARROW,
            ALMPositionNameLib.NARROW
        );
        _farms[i++] = _makeGammaQuickSwapMerklFarm(
            GAMMA_QUICKSWAP_WMATIC_WETH_WIDE,
            ALMPositionNameLib.WIDE
        );
        _farms[i++] = _makeGammaQuickSwapMerklFarm(
            GAMMA_QUICKSWAP_WBTC_USDCe_NARROW,
            ALMPositionNameLib.NARROW
        );
        _farms[i++] = _makeGammaQuickSwapMerklFarm(
            GAMMA_QUICKSWAP_WMATIC_USDT_NARROW,
            ALMPositionNameLib.NARROW
        );
        _farms[i++] = _makeGammaQuickSwapMerklFarm(
            GAMMA_QUICKSWAP_USDCe_WETH_WIDE,
            ALMPositionNameLib.WIDE
        );
        _farms[i++] = _makeGammaQuickSwapMerklFarm(
            GAMMA_QUICKSWAP_WBTC_WETH_WIDE,
            ALMPositionNameLib.WIDE
        );
        _farms[i++] = _makeGammaQuickSwapMerklFarm(
            GAMMA_QUICKSWAP_WETH_USDT_NARROW,
            ALMPositionNameLib.NARROW
        );
        _farms[i++] = _makeGammaQuickSwapMerklFarm(
            GAMMA_QUICKSWAP_WMATIC_USDCe_WIDE,
            ALMPositionNameLib.WIDE
        );
        _farms[i++] = _makeGammaQuickSwapMerklFarm(
            GAMMA_QUICKSWAP_WBTC_USDCe_WIDE,
            ALMPositionNameLib.WIDE
        );
        _farms[i++] = _makeGammaQuickSwapMerklFarm(
            GAMMA_QUICKSWAP_WETH_USDT_WIDE,
            ALMPositionNameLib.WIDE
        );
        _farms[i++] = _makeGammaQuickSwapMerklFarm(
            GAMMA_QUICKSWAP_WMATIC_USDT_WIDE,
            ALMPositionNameLib.WIDE
        );
        //endregion --  Gamma QuickSwap farms -----
    }

    function farms2() public pure returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](2);
        address[] memory rewardAssets;
        address[] memory addresses;
        uint[] memory nums;
        int24[] memory ticks;

        //region ----- QuickSwap V3 farms -----
        // [17] Earn dQUICK, WMATIC by static position in USDCe/USDC pool on QuickSwap V3
        rewardAssets = new address[](2);
        rewardAssets[0] = TOKEN_dQUICK;
        rewardAssets[1] = TOKEN_WMATIC;
        addresses = new address[](1);
        addresses[0] = QUICKSWAP_POSITION_MANAGER;
        nums = new uint[](0);
        ticks = new int24[](2);
        ticks[0] = -60;
        ticks[1] = 60;
        _farms[0] = IFactory.Farm({
            status: 0,
            pool: POOL_QUICKSWAPV3_USDCe_USDC,
            strategyLogicId: StrategyIdLib.QUICKSWAP_STATIC_MERKL_FARM,
            rewardAssets: rewardAssets,
            addresses: addresses,
            nums: nums,
            ticks: ticks
        });
        //endregion -- QuickSwap V3 farms -----

        // [18]
        rewardAssets = new address[](1);
        rewardAssets[0] = TOKEN_COMP;
        addresses = new address[](2);
        addresses[0] = COMPOUND_COMET;
        addresses[1] = COMPOUND_COMET_REWARDS;
        nums = new uint[](0);
        ticks = new int24[](0);
        _farms[1] = IFactory.Farm({
            status: 0,
            pool: address(0),
            strategyLogicId: StrategyIdLib.COMPOUND_FARM,
            rewardAssets: rewardAssets,
            addresses: addresses,
            nums: nums,
            ticks: ticks
        });
    }

    function farms3() public pure returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](6);
        address[] memory rewardAssets;
        address[] memory addresses;
        uint[] memory nums;
        int24[] memory ticks;

        // [18]
        rewardAssets = new address[](1);
        rewardAssets[0] = TOKEN_dQUICK;
        addresses = new address[](1);
        addresses[0] = DEFIEDGE_STRATEGY_WMATIC_WETH_NARROW_1;
        nums = new uint[](1);
        nums[0] = 0; // NARROW
        ticks = new int24[](0);
        _farms[0] = IFactory.Farm({
            status: 0,
            pool: POOL_QUICKSWAPV3_WMATIC_WETH,
            strategyLogicId: StrategyIdLib.DEFIEDGE_QUICKSWAP_MERKL_FARM,
            rewardAssets: rewardAssets,
            addresses: addresses,
            nums: nums,
            ticks: ticks
        });

        // [19]
        rewardAssets = new address[](1);
        rewardAssets[0] = TOKEN_dQUICK;
        addresses = new address[](1);
        addresses[0] = DEFIEDGE_STRATEGY_WMATIC_WETH_NARROW_2;
        nums = new uint[](1);
        nums[0] = 0; // NARROW
        ticks = new int24[](0);
        _farms[1] = IFactory.Farm({
            status: 0,
            pool: POOL_QUICKSWAPV3_WMATIC_WETH,
            strategyLogicId: StrategyIdLib.DEFIEDGE_QUICKSWAP_MERKL_FARM,
            rewardAssets: rewardAssets,
            addresses: addresses,
            nums: nums,
            ticks: ticks
        });

        // [20]
        rewardAssets = new address[](1);
        rewardAssets[0] = TOKEN_dQUICK;
        addresses = new address[](1);
        addresses[0] = DEFIEDGE_STRATEGY_WMATIC_USDC_NARROW;
        nums = new uint[](1);
        nums[0] = 0; // NARROW
        ticks = new int24[](0);
        _farms[2] = IFactory.Farm({
            status: 0,
            pool: POOL_QUICKSWAPV3_WMATIC_USDCe,
            strategyLogicId: StrategyIdLib.DEFIEDGE_QUICKSWAP_MERKL_FARM,
            rewardAssets: rewardAssets,
            addresses: addresses,
            nums: nums,
            ticks: ticks
        });

        // [21]
        rewardAssets = new address[](2);
        rewardAssets[0] = TOKEN_dQUICK;
        rewardAssets[1] = TOKEN_ICHI;
        addresses = new address[](1);
        addresses[0] = ICHI_QUICKSWAP_WMATIC_USDT;
        nums = new uint[](0);
        ticks = new int24[](0);
        _farms[3] = IFactory.Farm({
            status: 0,
            pool: POOL_QUICKSWAPV3_WMATIC_USDT,
            strategyLogicId: StrategyIdLib.ICHI_QUICKSWAP_MERKL_FARM,
            rewardAssets: rewardAssets,
            addresses: addresses,
            nums: nums,
            ticks: ticks
        });

        // [22]
        rewardAssets = new address[](2);
        rewardAssets[0] = TOKEN_dQUICK;
        rewardAssets[1] = TOKEN_ICHI;
        addresses = new address[](1);
        addresses[0] = ICHI_QUICKSWAP_WBTC_WETH;
        nums = new uint[](0);
        ticks = new int24[](0);
        _farms[4] = IFactory.Farm({
            status: 0,
            pool: POOL_QUICKSWAPV3_WBTC_WETH,
            strategyLogicId: StrategyIdLib.ICHI_QUICKSWAP_MERKL_FARM,
            rewardAssets: rewardAssets,
            addresses: addresses,
            nums: nums,
            ticks: ticks
        });

        // [23]
        rewardAssets = new address[](2);
        rewardAssets[0] = TOKEN_dQUICK;
        rewardAssets[1] = TOKEN_ICHI;
        addresses = new address[](1);
        addresses[0] = ICHI_QUICKSWAP_WETH_USDT;
        nums = new uint[](0);
        ticks = new int24[](0);
        _farms[5] = IFactory.Farm({
            status: 0,
            pool: POOL_QUICKSWAPV3_WETH_USDT,
            strategyLogicId: StrategyIdLib.ICHI_QUICKSWAP_MERKL_FARM,
            rewardAssets: rewardAssets,
            addresses: addresses,
            nums: nums,
            ticks: ticks
        });
    }

    // ichi retro part 1
    function farms4() public view returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](2);
        uint i;

        // [24]
        _farms[i++] = _makeIchiRetroMerklFarm(ICHI_RETRO_WMATIC_WETH_MATIC);
        // [25]
        _farms[i++] = _makeIchiRetroMerklFarm(ICHI_RETRO_WMATIC_USDCe_MATIC);
    }

    // ichi retro part 2
    function farms5() public view returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](3);
        uint i;

        // [26]
        _farms[i++] = _makeIchiRetroMerklFarm(ICHI_RETRO_WMATIC_WETH_ETH);
        // [27]
        _farms[i++] = _makeIchiRetroMerklFarm(ICHI_RETRO_WMATIC_USDCe_USDC);
        // [28]
        _farms[i++] = _makeIchiRetroMerklFarm(ICHI_RETRO_WBTC_WETH_ETH);
    }

    // gamma retro
    function farms6() public view returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](3);
        uint i;

        // [29]
        _farms[i++] = _makeGammaRetroMerklFarm(
            GAMMA_RETRO_WMATIC_USDCe_NARROW,
            ALMPositionNameLib.NARROW
        );

        // [30]
        _farms[i++] = _makeGammaRetroMerklFarm(
            GAMMA_RETRO_WMATIC_WETH_NARROW,
            ALMPositionNameLib.NARROW
        );

        // [31]
        _farms[i++] = _makeGammaRetroMerklFarm(
            GAMMA_RETRO_WBTC_WETH_WIDE,
            ALMPositionNameLib.WIDE
        );
    }

    // quickswap USDC native gamma
    function farms7() public view returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](2);
        uint i;

        // [32]
        _farms[i++] = _makeGammaQuickSwapMerklFarm(
            GAMMA_QUICKSWAP_USDC_WETH_NARROW,
            ALMPositionNameLib.NARROW
        );

        // [33]
        _farms[i++] = _makeGammaQuickSwapMerklFarm(
            GAMMA_QUICKSWAP_WMATIC_USDC_NARROW,
            ALMPositionNameLib.NARROW
        );
    }

    function farms8() public view returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](4);
        uint i;

        // [34]
        _farms[i++] = _makeCurveConvexFarm(
            POOL_CURVE_crvUSD_USDCe,
            CONVEX_REWARD_POOL_crvUSD_USDCe
        );
        // [35]
        _farms[i++] = _makeCurveConvexFarm(
            POOL_CURVE_crvUSD_USDT,
            CONVEX_REWARD_POOL_crvUSD_USDT
        );
        // [36]
        _farms[i++] = _makeCurveConvexFarm(
            POOL_CURVE_crvUSD_DAI,
            CONVEX_REWARD_POOL_crvUSD_DAI
        );
        // [37]
        _farms[i++] = _makeCurveConvexFarm(
            POOL_CURVE_crvUSD_USDC,
            CONVEX_REWARD_POOL_crvUSD_USDC
        );
    }

    // steer quickswap
    function farms9() public view returns (IFactory.Farm[] memory _farms) {
        _farms = new IFactory.Farm[](2);
        uint i;

        // [38]
        _farms[i++] = _makeSteerQuickSwapMerklFarm(
            STEER_STRATEGY_WMATIC_USDC,
            ALMPositionNameLib.NARROW
        );
        // [39]
        _farms[i++] = _makeSteerQuickSwapMerklFarm(
            STEER_STRATEGY_WBTC_WETH,
            ALMPositionNameLib.NARROW
        );
    }
    function _makeCurveConvexFarm(
        address curvePool,
        address convexRewardPool
    ) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        uint rewardTokensLength = IConvexRewardPool(convexRewardPool)
            .rewardLength();
        farm.status = 0;
        // pool address can be extracted from convexRewardPool here: curveGauge() -> lp_token()
        farm.pool = curvePool;
        farm.strategyLogicId = StrategyIdLib.CURVE_CONVEX_FARM;
        farm.rewardAssets = new address[](rewardTokensLength);
        for (uint i; i < rewardTokensLength; ++i) {
            IConvexRewardPool.RewardType memory r = IConvexRewardPool(
                convexRewardPool
            ).rewards(i);
            farm.rewardAssets[i] = r.reward_token;
        }
        farm.addresses = new address[](1);
        farm.addresses[0] = convexRewardPool;
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeGammaQuickSwapMerklFarm(
        address hypervisor,
        uint preset
    ) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IHypervisor(hypervisor).pool();
        farm.strategyLogicId = StrategyIdLib.GAMMA_QUICKSWAP_MERKL_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = TOKEN_dQUICK;
        farm.addresses = new address[](2);
        farm.addresses[0] = GAMMA_QUICKSWAP_UNIPROXY;
        farm.addresses[1] = hypervisor;
        farm.nums = new uint[](1);
        farm.nums[0] = preset;
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeSteerQuickSwapMerklFarm(
        address hypervisor,
        uint preset
    ) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IHypervisor(hypervisor).pool();
        farm.strategyLogicId = StrategyIdLib.STEER_QUICKSWAP_MERKL_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = TOKEN_USDC;
        farm.addresses = new address[](1);
        farm.addresses[0] = hypervisor;
        farm.nums = new uint[](1);
        farm.nums[0] = preset;
        farm.ticks = new int24[](0);
        return farm;
    }
    
    function _makeGammaRetroMerklFarm(
        address hypervisor,
        uint preset
    ) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IHypervisor(hypervisor).pool();
        farm.strategyLogicId = StrategyIdLib.GAMMA_RETRO_MERKL_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = TOKEN_oRETRO;
        farm.addresses = new address[](7);
        farm.addresses[0] = GAMMA_RETRO_UNIPROXY;
        farm.addresses[1] = hypervisor;
        farm.addresses[2] = TOKEN_CASH;
        farm.addresses[3] = POOL_RETRO_USDCe_CASH_100;
        farm.addresses[4] = POOL_RETRO_oRETRO_RETRO_10000;
        farm.addresses[5] = POOL_RETRO_CASH_RETRO_10000;
        farm.addresses[6] = RETRO_QUOTER;
        farm.nums = new uint[](1);
        farm.nums[0] = preset;
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeIchiRetroMerklFarm(
        address underlyingIchi
    ) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IICHIVault(underlyingIchi).pool();
        farm.strategyLogicId = StrategyIdLib.ICHI_RETRO_MERKL_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = TOKEN_oRETRO;
        farm.addresses = new address[](6);
        farm.addresses[0] = underlyingIchi;
        farm.addresses[1] = TOKEN_CASH;
        farm.addresses[2] = POOL_RETRO_USDCe_CASH_100;
        farm.addresses[3] = POOL_RETRO_oRETRO_RETRO_10000;
        farm.addresses[4] = POOL_RETRO_CASH_RETRO_10000;
        farm.addresses[5] = RETRO_QUOTER;
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    function testPolygonLib() external {}
}
