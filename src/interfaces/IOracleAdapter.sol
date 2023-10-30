// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @dev Read oracle prices
/// @author Alien Deployer (https://github.com/a17)
interface IOracleAdapter {
    /// @notice Asset USD price with 18 decimals
    function getPrice(address asset) external view returns (uint price, uint timestamp);

    function getAllPrices() external view returns (address[] memory assets_, uint[] memory prices, uint[] memory timestamps);

    function assets() external view returns (address[] memory);
}
