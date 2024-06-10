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

/// @dev Arbitrum network [chainId: 42161] data library

//   AAAAA  RRRR   BBBB    III TTTTTT RRRR   UU   UU MMMM   MMMM
//  AA   AA RR  RR BB  BB  III   TT   RR  RR UU   UU MM MM MM MM
//  AA   AA RRRR   BBBBB   III   TT   RRRR   UU   UU MM  MMM  MM
//  AAAAAAA RR  RR BB  BB  III   TT   RR  RR UU   UU MM       MM
//  AA   AA RR   RR BBBB   III   TT   RR   RR UUUUU  MM       MM

/// @author Alien Deployer (https://github.com/a17)
library ArbitrumLib {
    // initial addresses
    address public constant MULTISIG = 0xE28e3Ee2bD10328bC8A7299B83A80d2E1ddD8708;

    // ERC20
    address public constant TOKEN_ARB = 0x912CE59144191C1204E64559FE8253a0e49E6548;
    address public constant TOKEN_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address public constant TOKEN_USDT = 0xfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9;
    address public constant TOKEN_DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address public constant TOKEN_USDCe = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address public constant TOKEN_WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
    address public constant TOKEN_weETH = 0x35751007a407ca6FEFfE80b3cB397736D2cf4dbe;
    address public constant TOKEN_frxETH = 0x178412e79c25968a32e89b11f63B33F733770c2A;
    address public constant TOKEN_FRAX = 0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F;
    
    // AMMs

    // Oracles
    address public constant ORACLE_CHAINLINK_USDC_USD = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
    address public constant ORACLE_CHAINLINK_USDT_USD = 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7;
    address public constant ORACLE_CHAINLINK_DAI_USD = 0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB;

    // Compound

    // DeX aggregators

    function platformDeployParams() internal pure returns(IPlatformDeployer.DeployPlatformParams memory p){
        p.multisig = MULTISIG;
        p.version = "24.06.0-alpha";
        p.buildingPermitToken = address(0);
        p.buildingPayPerVaultToken = TOKEN_ARB;
        p.networkName = "Arbitrum";
        p.networkExtra = CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x2959bc), bytes3(0x000000)));
        p.targetExchangeAsset = address(0);
        p.gelatoAutomate = GELATO_AUTOMATE;
        p.gelatoMinBalance = 1e16;
        p.gelatoDepositAmount = 2e16;
    }

    function deployAndSetupInfrastructure(address platform, bool showLog) internal {
        IFactory factory = IFactory(IPlatform(platform).factory());
        
        //region ----- Deployed Platform -----
        if(showLog) {
            console.log("Deployed Statbility platform", IPlatform(platform).platformVersion());
            console.log("Platform addres:", platform);
        }
        //endregion -- Deployed Platform ----

        //region ----- Deploy and setup vault types -----
        _addVaultType(factory, VaultTypeLib.COMPOUNDING, address(new CVault()), 100e6);
        //endregion -- Deploy and setup valut types -----

        //region -----Deploy and setup oracle adapters -----
        IPriceReader priceReader = PriceReader(IPlatform(platform).priceReader());
        //Chainlnk
        {
            Proxy proxy = new Proxy();
            proxy.initProxy(address(new ChainlinkAdapter()));
            ChainlinkAdapter chainlinkAdapter = ChainlinkAdapter(address(proxy));
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
            LogDeployLib.logDeployAndSetupOracleAdapter("ChainLink", address(chainlinkAdapter), showLog);
        }
        //endregion -- Deploy and setup oracle adapters -----

        //region ----- Deploy AMM adapters -----
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.UNISWAPV3);
        DeployAdapterLib.deployAmmAdapter(platform, AmmAdapterIdLib.CURVE);
        LogDeployLib.deployAmmAdapter(platform, showLog);
        //endregion -- Deploy AMM adapters -----

        //region ----- Setup Swapper -----
        {
            (ISwapper.AddPoolData[] memory bcPools, ISwapper.AddPoolData[] memory pools) = routes();
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
            thresholdAmount[4] = 1e15;
            thresholdAmount[5] = 1e15;
            thresholdAmount[6] = 1e15;
            thresholdAmount[7] = 1e15;
            swaper.setThresholds(tokenIn, thresholdAmount);
            LogDeployLib.logSetupSwapper(showLog);
        }
        //endregion -- Setup Swapper -----

        //region ----- Add farms -----
        factory.addFarms(farms());
        LogDeployLib.logAddedFarms(address(factory), showLog);
        //endregion -- Add farms -----

        //region ----- Deploy strategy logics -----
        _addStrategyLogic(factory, StrategyIdLib.COMPOUND_FARM, address(new CompoundFarmStrategy()), true);
        LogDeployLib.logDeployStrategies(platform, showLog);

        //endregion -- Deploy strategy logics -----

        function _addVaultType(IFactory factory, string id, address implementation, uint buildingPrice) internal {
            factory.setVaultConfig(
                IFactory.VaultConfig({
                    vaultType: id,
                    implementation: implementation,
                    deployAllowed: true,
                    upgradeAllowed: true,
                    buildingPrice: buildingPrice
                })
            )
        }
        function _addStrategyLogic(IFactory factory, string memory id, address implementation, bool farming) internal{
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
    }
}
