// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "../../core/base/UpgradeableProxy.sol";
import "../../interfaces/IControllable.sol";
import "../../interfaces/IPlatform.sol";
import "../../interfaces/IFactory.sol";
import "../../interfaces/IStrategyProxy.sol";

/// @title EIP1967 Upgradeable proxy implementation for built by Factory strategies.
contract StrategyProxy is UpgradeableProxy, IStrategyProxy {
    /// @dev Strategy logic id
    bytes32 private constant _ID_SLOT = bytes32(uint256(keccak256("eip1967.strategyProxy.id")) - 1);

    function initStrategyProxy(string memory id) external {
        bytes32 strategyIdHash = keccak256(abi.encodePacked(id));
        //slither-disable-next-line unused-return
        (,address strategyImplementation,,,,) = IFactory(msg.sender).strategyLogicConfig(strategyIdHash);
        _init(strategyImplementation);
        bytes32 slot = _ID_SLOT;
        assembly {
            sstore(slot, strategyIdHash)
        }
    }

    function upgrade() external {
        require(msg.sender == IPlatform(IControllable(address(this)).platform()).factory(), "Proxy: Forbidden");
        bytes32 strategyIdHash;
        bytes32 slot = _ID_SLOT;
        assembly {
            strategyIdHash := sload(slot)
        }
        //slither-disable-next-line unused-return
        (,address strategyImplementation,,,,) = IFactory(msg.sender).strategyLogicConfig(strategyIdHash);
        _upgradeTo(strategyImplementation);
    }

    function implementation() external view returns (address) {
        return _implementation();
    }

    function STRATEGY_IMPLEMENTATION_LOGIC_ID_HASH() external view returns (bytes32) {
        bytes32 idHash;
        bytes32 slot = _ID_SLOT;
        assembly {
            idHash := sload(slot)
        }
        return idHash;
    }
}
