// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../src/interfaces/IPlatformDeployer.sol";

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
}
