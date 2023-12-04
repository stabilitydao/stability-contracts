// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/UpgradeableProxy.sol";
import "../../interfaces/IControllable.sol";
import "../../interfaces/IProxy.sol";

/// @title Proxy for Stability Platform core contracts.
/// @dev ERC-1967: Proxy Storage Slots used.
/// @author JodsMigel (https://github.com/JodsMigel)
contract Proxy is UpgradeableProxy, IProxy {
    /// @inheritdoc IProxy
    function initProxy(address logic_) external override {
        _init(logic_);
    }

    /// @inheritdoc IProxy
    //slither-disable-next-line naming-convention
    function upgrade(address _newImplementation) external override {
        if (IControllable(address(this)).platform() != msg.sender) {
            revert IControllable.NotPlatform();
        }
        _upgradeTo(_newImplementation);
        // the new contract must have the same ABI and you must have the power to change it again
        if (IControllable(address(this)).platform() != msg.sender) {
            revert IControllable.NotPlatform();
        }
    }

    /// @inheritdoc IProxy
    function implementation() external view override returns (address) {
        return _implementation();
    }
}
