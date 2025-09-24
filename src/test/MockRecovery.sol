// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRecovery} from "../interfaces/IRecovery.sol";

contract MockRecovery is IRecovery {
    address[] public registeredTokens;

    function initialize(address platform_) external pure {
        platform_;
    }

    function registerAssets(address[] memory tokens) external {
        registeredTokens = tokens;
    }

    function swapAssetsToRecoveryTokens(uint indexFirstRecoveryPool1) external {
        indexFirstRecoveryPool1;
        // todo
    }

    function registeredTokensLength() external view returns (uint) {
        return registeredTokens.length;
    }

}