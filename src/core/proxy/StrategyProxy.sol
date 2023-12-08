// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../core/base/UpgradeableProxy.sol";
import "../../interfaces/IControllable.sol";
import "../../interfaces/IPlatform.sol";
import "../../interfaces/IFactory.sol";
import "../../interfaces/IStrategyProxy.sol";

/// @title EIP1967 Upgradeable proxy implementation for built by Factory strategies.
/// @author Alien Deployer (https://github.com/a17)
/// @author JodsMigel (https://github.com/JodsMigel)
/// @author Jude (https://github.com/iammrjude)
contract StrategyProxy is UpgradeableProxy, IStrategyProxy {
    /// @dev Strategy logic id
    bytes32 private constant _ID_SLOT = bytes32(uint(keccak256("eip1967.strategyProxy.id")) - 1);

    /// @inheritdoc IStrategyProxy
    function initStrategyProxy(string memory id) external {
        bytes32 strategyIdHash = keccak256(abi.encodePacked(id));
        //slither-disable-next-line unused-return
        IFactory.StrategyLogicConfig memory strategyConfig = IFactory(msg.sender).strategyLogicConfig(strategyIdHash);
        address strategyImplementation = strategyConfig.implementation;
        _init(strategyImplementation);
        bytes32 slot = _ID_SLOT;
        //slither-disable-next-line assembly
        assembly {
            sstore(slot, strategyIdHash)
        }
    }

    /// @inheritdoc IStrategyProxy
    function upgrade() external {
        if (IPlatform(IControllable(address(this)).platform()).factory() != msg.sender) {
            revert IControllable.NotFactory();
        }
        bytes32 strategyIdHash;
        bytes32 slot = _ID_SLOT;
        //slither-disable-next-line assembly
        assembly {
            strategyIdHash := sload(slot)
        }
        //slither-disable-next-line unused-return
        IFactory.StrategyLogicConfig memory strategyConfig = IFactory(msg.sender).strategyLogicConfig(strategyIdHash);
        address strategyImplementation = strategyConfig.implementation;
        _upgradeTo(strategyImplementation);
    }

    /// @inheritdoc IStrategyProxy
    function implementation() external view returns (address) {
        return _implementation();
    }

    /// @inheritdoc IStrategyProxy
    function strategyImplementationLogicIdHash() external view returns (bytes32) {
        bytes32 idHash;
        bytes32 slot = _ID_SLOT;
        //slither-disable-next-line assembly
        assembly {
            idHash := sload(slot)
        }
        return idHash;
    }
}
