// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "../base/UpgradeableProxy.sol";
import "../../interfaces/IControllable.sol";
import "../../interfaces/IProxy.sol";

/// @title EIP1967 Upgradable proxy implementation.
contract Proxy is UpgradeableProxy, IProxy {

    /// @notice Version of the contract
    /// @dev Should be incremented when contract changed
    string public constant PROXY_VERSION = "1.0.0";

    /// @dev Initialize proxy implementation. Need to call after deploy new proxy.
    function initProxy(address _logic) external override {
        _init(_logic);
    }

    /// @notice Upgrade contract logic
    /// @dev Upgrade allowed only for Platform and should be done only after time-lock period
    /// @param _newImplementation Implementation address
    function upgrade(address _newImplementation) external override {
        require(IControllable(address(this)).platform() == msg.sender, "Proxy: Forbidden");
        _upgradeTo(_newImplementation);
        // the new contract must have the same ABI and you must have the power to change it again
        require(IControllable(address(this)).platform() == msg.sender, "Proxy: Wrong implementation");
    }

    /// @notice Return current logic implementation
    function implementation() external override view returns (address) {
        return _implementation();
    }
}
