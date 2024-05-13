// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IBoostedStrategy {
    /// @notice Linked Booster
    function booster() external view returns (address);
}
