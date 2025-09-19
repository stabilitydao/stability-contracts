// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IRecoveryContract {

    /// @dev Init
    function initialize(address platform_) external;


    /// @notice Revenue Router calls this function to notify about the transferred amount of tokens
    /// @param tokens Addresses of the tokens that were transferred
    /// @param amounts Amounts of the transferred tokens
    function registerTransferredAmounts(address[] memory tokens, uint[] memory amounts) external;
}
