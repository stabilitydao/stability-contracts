// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {UpgradeableProxy} from "../../core/base/UpgradeableProxy.sol";
import {IControllable} from "../../interfaces/IControllable.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IMetaVaultFactory} from "../../interfaces/IMetaVaultFactory.sol";
import {IMetaProxy} from "../../interfaces/IMetaProxy.sol";

/// @title EIP1967 Upgradeable proxy implementation for MetaVaults
///         ┏┓┏┳┓┏┓┳┓┳┓ ┳┏┳┓┓┏  ┏┓┓ ┏┓┏┳┓┏┓┏┓┳┓┳┳┓
///         ┗┓ ┃ ┣┫┣┫┃┃ ┃ ┃ ┗┫  ┃┃┃ ┣┫ ┃ ┣ ┃┃┣┫┃┃┃
///         ┗┛ ┻ ┛┗┻┛┻┗┛┻ ┻ ┗┛  ┣┛┗┛┛┗ ┻ ┻ ┗┛┛┗┛ ┗
/// @author Alien Deployer (https://github.com/a17)
contract MetaVaultProxy is UpgradeableProxy, IMetaProxy {
    /// @inheritdoc IMetaProxy
    function initProxy() external {
        _init(_getImplementation());
    }

    /// @inheritdoc IMetaProxy
    function upgrade() external {
        require(msg.sender == IPlatform(IControllable(address(this)).platform()).metaVaultFactory(), ProxyForbidden());
        _upgradeTo(_getImplementation());
    }

    /// @inheritdoc IMetaProxy
    function implementation() external view returns (address) {
        return _implementation();
    }

    function _getImplementation() internal view returns (address) {
        return IMetaVaultFactory(msg.sender).metaVaultImplementation();
    }
}
