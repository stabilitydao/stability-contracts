// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IAggregatorInterfaceMinimal {

    /// @notice Latest USD price with 8 decimals
    function latestAnswer() external view returns (int);

}
