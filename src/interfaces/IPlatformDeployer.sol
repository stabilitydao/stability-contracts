// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IVaultPriceOracle} from "./IVaultPriceOracle.sol";

interface IPlatformDeployer {
    struct DeployPlatformParams {
        address multisig;
        string version;
        address targetExchangeAsset;
        uint fee;
    }
}
