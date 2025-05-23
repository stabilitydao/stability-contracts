// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
    ERC4626Upgradeable,
    IERC20,
    IERC20Metadata
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {Controllable, IControllable} from "../core/base/Controllable.sol";
import {IWrappedMetaVault} from "../interfaces/IWrappedMetaVault.sol";
import {IStabilityVault} from "../interfaces/IStabilityVault.sol";

/// @title Wrapped rebase MetaVault
/// @author Alien Deployer (https://github.com/a17)
contract MockWrappedMetaVaultUpgrade is Controllable, ERC4626Upgradeable, IWrappedMetaVault {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "99.0.0";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IWrappedMetaVault
    function initialize(address, address) public {}

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IWrappedMetaVault
    function metaVault() external view returns (address) {}
}
