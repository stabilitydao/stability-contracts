// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Controllable, IControllable} from "./base/Controllable.sol";
import {IMetaVaultFactory} from "../interfaces/IMetaVaultFactory.sol";

/// @title Factory for deploying MetaVaults, MultiVaults and wrappers
/// @author Alien Deployer (https://github.com/a17)
contract MetaVaultFactory is Controllable, IMetaVaultFactory {
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
        emit NewImplementation(newImplementation);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IMetaVaultFactory
    function metaVaultImplementation() external view returns (address) {
        return _getStorage().metaVaultImplementation;
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
