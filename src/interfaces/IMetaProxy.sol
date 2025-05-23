// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @dev Interface of minimal dedicated proxy contract
interface IMetaProxy {
    error ProxyForbidden();

    /// @notice Initialize proxy
    function initProxy() external;

    /// @notice Upgrade proxied implementation
    function upgrade() external;

    /// @notice Current implementation
    /// @return Address of the implementation contract
    function implementation() external view returns (address);
}
