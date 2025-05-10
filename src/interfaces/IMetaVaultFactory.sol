// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMetaVaultFactory {
    event NewImplementation(address implementation);

    /// @custom:storage-location erc7201:stability.MetaVaultFactory
    struct MetaVaultFactoryStorage {
        /// @inheritdoc IMetaVaultFactory
        address metaVaultImplementation;
    }

    /// @notice Initialize proxied contract
    function initialize(address platform) external;

    /// @notice Update MetaVault implementation address
    /// @param newImplementation Address of new deployed MetaVault implementation
    function setMetaVaultImplementation(address newImplementation) external;

    /// @notice Get address of MetaVault implementation
    /// @return MetaVault implementation address
    function metaVaultImplementation() external view returns (address);
}
