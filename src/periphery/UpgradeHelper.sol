// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPlatform} from "../interfaces/IPlatform.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IVault} from "../interfaces/IVault.sol";
import {VaultTypeLib} from "../core/libs/VaultTypeLib.sol";
import {VaultStatusLib} from "../core/libs/VaultStatusLib.sol";

/// @title UpgradeHelper
/// Changelog:
///   2.0.0: Breaking change. Renamed the public variable `platform` to `PLATFORM`.
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
contract UpgradeHelper {
    string public constant VERSION = "2.0.0";

    // slither-disable-next-line naming-convention
    address public immutable PLATFORM;

    constructor(address platform_) {
        PLATFORM = platform_;
    }

    function upgradeVaults() external returns (uint upgraded) {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        (, address implementation,,,) = factory.vaultConfig(keccak256(abi.encodePacked(VaultTypeLib.COMPOUNDING)));
        string memory lastVersion = IControllable(implementation).VERSION();
        address[] memory vaults = factory.deployedVaults();
        uint len = vaults.length;
        for (uint i; i < len; ++i) {
            uint status = factory.vaultStatus(vaults[i]);
            if (status != VaultStatusLib.ACTIVE) {
                continue;
            }
            string memory curVersion = IControllable(vaults[i]).VERSION();
            if (!_eq(lastVersion, curVersion)) {
                factory.upgradeVaultProxy(vaults[i]);
                upgraded++;
            }
        }
    }

    function upgradeStrategies() external returns (uint upgraded) {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        address[] memory vaults = factory.deployedVaults();
        uint len = vaults.length;
        for (uint i; i < len; ++i) {
            IStrategy strategy = IVault(vaults[i]).strategy();
            string memory strategyId = strategy.strategyLogicId();
            IFactory.StrategyLogicConfig memory strategyConfig =
                factory.strategyLogicConfig(keccak256(bytes(strategyId)));
            if (!strategyConfig.upgradeAllowed) {
                continue;
            }

            string memory lastVersion = IControllable(strategyConfig.implementation).VERSION();
            string memory curVersion = IControllable(address(strategy)).VERSION();
            if (!_eq(lastVersion, curVersion)) {
                factory.upgradeStrategyProxy(address(strategy));
                upgraded++;
            }
        }
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
