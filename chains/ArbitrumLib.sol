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


/// @dev Arbitrum network [chainId: 42161] data library

//   AAAAA  RRRR   BBBB    III  TTTTTT UU   UU MMMM   MMMM
//  AA   AA RR  RR BB  BB  III    TT   UU   UU MM MM MM MM
//  AA   AA RRRR   BBBBB   III    TT   UU   UU MM  MMM  MM
//  AAAAAAA RR  RR BB  BB  III    TT   UU   UU MM       MM
//  AA   AA RR   RR BBBB   III    TT    UUUUU  MM       MM

/// @author Alien Deployer (https://github.com/a17)
library ArbitrumLib {
    // initial addresses
    address public constant MULTISIG = 0xE28e3Ee2bD10328bC8A7299B83A80d2E1ddD8708;

    // ERC20
    address public constant TOKEN_ARB = 0x912CE59144191C1204E64559FE8253a0e49E6548;
    address public constant TOKEN_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address public constant TOKEN_USDT = 0xfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9;
    address public constant TOKEN_DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    
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

    }
}
