// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Controllable, IControllable} from "./base/Controllable.sol";
import {IMetaVaultFactory} from "../interfaces/IMetaVaultFactory.sol";
import {IMetaProxy} from "../interfaces/IMetaProxy.sol";
import {MetaVaultProxy} from "./proxy/MetaVaultProxy.sol";
import {IMetaVault, EnumerableSet} from "../interfaces/IMetaVault.sol";
import {WrappedMetaVaultProxy} from "./proxy/WrappedMetaVaultProxy.sol";
import {IWrappedMetaVault} from "../interfaces/IWrappedMetaVault.sol";

/// @title Factory of MetaVaults and WrappedMetaVaults
/// @author Alien Deployer (https://github.com/a17)
contract MetaVaultFactory is Controllable, IMetaVaultFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.MetaVaultFactory")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant METAVAULTFACTORY_STORAGE_LOCATION =
        0x58b476403d8ac8a4d0530fd874c3ac691dfe1c48aec83d57fe82186c80386c00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IMetaVaultFactory
    function initialize(address platform_) public initializer {
        __Controllable_init(platform_);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IMetaVaultFactory
    function setMetaVaultImplementation(address newImplementation) external onlyGovernanceOrMultisig {
        MetaVaultFactoryStorage storage $ = _getStorage();
        $.metaVaultImplementation = newImplementation;
        emit NewMetaVaultImplementation(newImplementation);
    }

    /// @inheritdoc IMetaVaultFactory
    function setWrappedMetaVaultImplementation(address newImplementation) external onlyGovernanceOrMultisig {
        MetaVaultFactoryStorage storage $ = _getStorage();
        $.wrappedMetaVaultImplementation = newImplementation;
        emit NewWrappedMetaVaultImplementation(newImplementation);
    }

    /// @inheritdoc IMetaVaultFactory
    function deployMetaVault(
        bytes32 salt,
        string memory type_,
        address pegAsset_,
        string memory name_,
        string memory symbol_,
        address[] memory vaults_,
        uint[] memory proportions_
    ) external onlyOperator returns (address proxy) {
        proxy = address(new MetaVaultProxy{salt: salt}());
        IMetaProxy(proxy).initProxy();
        IMetaVault(proxy).initialize(platform(), type_, pegAsset_, name_, symbol_, vaults_, proportions_);

        MetaVaultFactoryStorage storage $ = _getStorage();
        $.metaVaults.add(proxy);

        emit NewMetaVault(proxy, type_, pegAsset_, name_, symbol_, vaults_, proportions_);
    }

    /// @inheritdoc IMetaVaultFactory
    function deployWrapper(bytes32 salt, address metaVault) external onlyOperator returns (address proxy) {
        proxy = address(new WrappedMetaVaultProxy{salt: salt}());
        IMetaProxy(proxy).initProxy();
        IWrappedMetaVault(proxy).initialize(platform(), metaVault);

        MetaVaultFactoryStorage storage $ = _getStorage();
        require($.wrapper[metaVault] == address(0), AlreadyExist());
        $.wrapper[metaVault] = proxy;

        emit NewWrappedMetaVault(proxy, metaVault);
    }

    /// @inheritdoc IMetaVaultFactory
    function upgradeMetaProxies(address[] memory metaProxies) external onlyOperator {
        uint len = metaProxies.length;
        for (uint i; i < len; ++i) {
            IMetaProxy(metaProxies[i]).upgrade();
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IMetaVaultFactory
    function metaVaultImplementation() external view returns (address) {
        return _getStorage().metaVaultImplementation;
    }

    /// @inheritdoc IMetaVaultFactory
    function wrappedMetaVaultImplementation() external view returns (address) {
        return _getStorage().wrappedMetaVaultImplementation;
    }

    /// @inheritdoc IMetaVaultFactory
    function getMetaVaultProxyInitCodeHash() external pure returns (bytes32) {
        return keccak256(abi.encodePacked(type(MetaVaultProxy).creationCode));
    }

    /// @inheritdoc IMetaVaultFactory
    function getWrappedMetaVaultProxyInitCodeHash() external pure returns (bytes32) {
        return keccak256(abi.encodePacked(type(WrappedMetaVaultProxy).creationCode));
    }

    /// @inheritdoc IMetaVaultFactory
    function getCreate2Address(
        bytes32 salt,
        bytes32 initCodeHash,
        address thisAddress
    ) external pure returns (address) {
        return address(uint160(uint(keccak256(abi.encodePacked(bytes1(0xff), thisAddress, salt, initCodeHash)))));
    }

    /// @inheritdoc IMetaVaultFactory
    function metaVaults() external view returns (address[] memory) {
        return _getStorage().metaVaults.values();
    }

    /// @inheritdoc IMetaVaultFactory
    function wrapper(address metaVault) external view returns (address) {
        return _getStorage().wrapper[metaVault];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getStorage() private pure returns (MetaVaultFactoryStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := METAVAULTFACTORY_STORAGE_LOCATION
        }
    }
}
