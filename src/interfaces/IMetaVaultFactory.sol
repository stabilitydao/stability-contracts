// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface IMetaVaultFactory {
    event NewMetaVaultImplementation(address implementation);
    event NewWrappedMetaVaultImplementation(address implementation);
    event NewRecoveryTokenImplementation(address implementation);
    event NewMetaVault(
        address metaVault,
        string type_,
        address pegAsset_,
        string name_,
        string symbol_,
        address[] vaults_,
        uint[] proportions_
    );
    event NewWrappedMetaVault(address wrappedMetaVault, address metaVault);
    event NewRecoveryToken(address recoveryToken, address target);

    /// @custom:storage-location erc7201:stability.MetaVaultFactory
    struct MetaVaultFactoryStorage {
        /// @inheritdoc IMetaVaultFactory
        address metaVaultImplementation;
        /// @inheritdoc IMetaVaultFactory
        address wrappedMetaVaultImplementation;
        /// @inheritdoc IMetaVaultFactory
        EnumerableSet.AddressSet metaVaults;
        /// @inheritdoc IMetaVaultFactory
        mapping(address metaVault => address wrappedMetaVault) wrapper;
        /// @inheritdoc IMetaVaultFactory
        address recoveryTokenImplementation;
    }

    /// @notice Initialize proxied contract
    function initialize(address platform) external;

    /// @notice Update MetaVault implementation address
    /// @param newImplementation Address of new deployed MetaVault implementation
    function setMetaVaultImplementation(address newImplementation) external;

    /// @notice Update Wrapped MetaVault implementation address
    /// @param newImplementation Address of new deployed Wrapped MetaVault implementation
    function setWrappedMetaVaultImplementation(address newImplementation) external;

    /// @notice Update RecoveryToken implementation address
    /// @param newImplementation Address of new deployed RecoveryToken implementation
    function setRecoveryTokenImplementation(address newImplementation) external;

    /// @notice Deploy new MetaVault
    /// @param salt Salt to get CREATE2 deployment address
    /// @param type_ MetaVault type
    /// @param pegAsset_ Asset to peg price. 0x00 is USD.
    /// @param name_ Name of vault
    /// @param symbol_ Symbol of vault
    /// @param vaults_ Underling vaults
    /// @param proportions_ Underling proportions
    /// @return proxy Address of deployed MetaVaultProxy contract
    function deployMetaVault(
        bytes32 salt,
        string memory type_,
        address pegAsset_,
        string memory name_,
        string memory symbol_,
        address[] memory vaults_,
        uint[] memory proportions_
    ) external returns (address proxy);

    /// @notice Deploy new WrappedMetaVault
    /// @param salt Salt to get CREATE2 deployment address
    /// @param metaVault MetaVault wrapped
    /// @return proxy Address of deployed WrappedMetaVaultProxy contract
    function deployWrapper(bytes32 salt, address metaVault) external returns (address proxy);

    /// @notice Deploy new RecoveryToken for target
    function deployRecoveryToken(bytes32 salt, address target) external returns (address proxy);

    /// @notice Upgrade MetaVaults and wrappers implementation
    /// @param metaProxies Addresses of proxies for upgrade
    function upgradeMetaProxies(address[] memory metaProxies) external;

    /// @notice Get address of MetaVault implementation
    /// @return MetaVault implementation address
    function metaVaultImplementation() external view returns (address);

    /// @notice Get address of Wrapped MetaVault implementation
    /// @return Wrapped MetaVault implementation address
    function wrappedMetaVaultImplementation() external view returns (address);

    /// @notice Get address of RecoveryToken implementation
    /// @return RecoveryToken implementation address
    function recoveryTokenImplementation() external view returns (address);

    /// @dev Get CREATE2 address
    /// @param salt Provided salt for CREATE2
    /// @param initCodeHash Hash of contract creationCode
    /// @param thisAddress Address of this factory
    /// @return Future deployment address
    function getCreate2Address(
        bytes32 salt,
        bytes32 initCodeHash,
        address thisAddress
    ) external pure returns (address);

    /// @dev Get keccak256 hash of MetaVaultProxy creationCode for CREATE2
    function getMetaVaultProxyInitCodeHash() external view returns (bytes32);

    /// @dev Get keccak256 hash of WrappedMetaVaultProxy creationCode for CREATE2
    function getWrappedMetaVaultProxyInitCodeHash() external view returns (bytes32);

    /// @dev Get keccak256 hash of RecoveryTokenProxy creationCode for CREATE2
    function getRecoveryTokenProxyInitCodeHash() external view returns (bytes32);

    /// @notice Deployed MetaVaults
    function metaVaults() external view returns (address[] memory);

    /// @notice Wrapper of MetaVault
    function wrapper(address metaVault) external view returns (address);
}
