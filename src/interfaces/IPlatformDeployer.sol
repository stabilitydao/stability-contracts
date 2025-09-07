// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IPlatformDeployer {
    struct DeployPlatformParams {
        address multisig;
        string version;
        address targetExchangeAsset;
        uint fee;
    }
}
