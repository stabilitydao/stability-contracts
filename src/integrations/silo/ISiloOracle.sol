// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ISiloOracle {
    /// @notice Hook function to call before `quote` function reads price
    /// @dev This hook function can be used to change state right before the price is read. For example it can be used
    ///      for curve read only reentrancy protection. In majority of implementations this will be an empty function.
    ///      WARNING: reverts are propagated to Silo so if `beforeQuote` reverts, Silo reverts as well.
    /// @param _baseToken Address of priced token
    function beforeQuote(address _baseToken) external;

    /// @return quoteAmount Returns quote price for _baseAmount of _baseToken
    /// @param _baseAmount Amount of priced token
    /// @param _baseToken Address of priced token
    function quote(uint _baseAmount, address _baseToken) external view returns (uint quoteAmount);

    /// @return address of token in which quote (price) is denominated
    function quoteToken() external view returns (address);
}
