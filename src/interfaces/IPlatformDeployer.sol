// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IPlatformDeployer {
    struct DeployPlatformParams {
        address multisig;
        string version;
        address buildingPermitToken;
        address buildingPayPerVaultToken;
        string networkName;
        bytes32 networkExtra;
        address targetExchangeAsset;
        address gelatoAutomate;
        uint gelatoMinBalance;
        uint gelatoDepositAmount;
        uint fee;
        uint feeShareVaultManager;
        uint feeShareStrategyLogic;
    }
}
