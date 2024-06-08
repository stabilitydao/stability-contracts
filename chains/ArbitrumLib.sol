// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../src/interfaces/IPlatformDeployer.sol";

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
    
    // AMMs

    // Oracles

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



}
