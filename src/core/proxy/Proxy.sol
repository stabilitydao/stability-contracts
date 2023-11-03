// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "../base/UpgradeableProxy.sol";
import "../../interfaces/IControllable.sol";
import "../../interfaces/IProxy.sol";

/// @title Proxy for Stability Platform core contracts.
/// @dev ERC-1967: Proxy Storage Slots used.
contract Proxy is UpgradeableProxy, IProxy {

    /// @notice Version of the contract
    /// @dev Should be incremented when contract changed
    /// todo remove?
    string public constant PROXY_VERSION = "1.0.0";

    /// @inheritdoc IProxy
    function initProxy(address logic_) external override {
        _init(logic_);
    }

    /// @inheritdoc IProxy
    function upgrade(address _newImplementation) external override {
        require(IControllable(address(this)).platform() == msg.sender, "Proxy: Forbidden");
        _upgradeTo(_newImplementation);
        // the new contract must have the same ABI and you must have the power to change it again
        require(IControllable(address(this)).platform() == msg.sender, "Proxy: Wrong implementation");
    }

    /// @inheritdoc IProxy
    function implementation() external override view returns (address) {
        return _implementation();
    }
}
