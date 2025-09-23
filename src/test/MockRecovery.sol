// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRecovery} from "../interfaces/IRecovery.sol";

contract MockRecovery is IRecovery {
    address[] public registeredTokens;
    uint[] public registeredAmounts;

    function initialize(address platform_) external {
        // nothing to do
    }


    /// @notice Revenue Router calls this function to notify about the transferred amount of tokens
    /// @param tokens Addresses of the tokens that were transferred
    /// @param amounts Amounts of the transferred tokens
    function registerTransferredAmounts(address[] memory tokens, uint[] memory amounts) external {
        registeredTokens = tokens;
        registeredAmounts = amounts;
    }

    function registeredTokensLength() external view returns (uint) {
        return registeredTokens.length;
    }

    function registeredAmountsLength() external view returns (uint) {
        return registeredAmounts.length;
    }
}