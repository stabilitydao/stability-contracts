// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../src/interfaces/IPlatformDeployer.sol";
import "../src/interfaces/IFactory.sol";
import "../src/core/proxy/Proxy.sol";
import "../script/libs/LogDeployLib.sol";

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

    // Oracles
    address public constant ORACLE_CHAINLINK_USDC_USD = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
    address public constant ORACLE_CHAINLINK_USDT_USD = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;
    address public constant ORACLE_CHAINLINK_ETH_USD = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

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
        _addVaultType(factory, VaultTypeLin.COMPOUNDING, address(new CVault()), 1e17);
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
            priceReader.addPriceFeed(address(chainlinkAdapter));
            LogDeployLib.logDeployAndSetupOracleAdapter("ChainLink", address(chainlinkAdapter), showLog);
        }
        //endregion -- Deploy and setup oracle adapters -----
    }
}
