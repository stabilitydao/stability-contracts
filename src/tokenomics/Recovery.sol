// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {
ERC20Upgradeable,
IERC20,
IERC20Metadata
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Controllable, IControllable, IPlatform} from "../core/base/Controllable.sol";
import {ERC20BurnableUpgradeable} from
"@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IRecovery} from "../interfaces/IRecovery.sol";

/// @title Recovery contract to swap assets on recovery tokens in recovery pools
/// @author dvpublic (https://github.com/dvpublic)
/// Changelog:
contract Recovery is Controllable, IRecovery {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.Recovery.sol")) - 1)) & ~bytes32(uint(0xff));
    bytes32 private constant _RECOVERY_STORAGE_LOCATION = 0x0; // todo

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.Recovery.sol
    struct RecoveryStorage {

        /// @notice UniswapV3 pools with recovery tokens
        EnumerableSet.AddressSet recoveryPools;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRecovery
    function initialize(address platform_) public initializer {
        __Controllable_init(platform_);
        RecoveryStorage storage $ = _getRecoveryTokenStorage();
        // todo
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function registerTransferredAmounts(address[] memory tokens, uint[] memory amounts) external {
        // todo only multisig or revenue router
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/


    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function _getRecoveryTokenStorage() internal pure returns (RecoveryStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _RECOVERY_STORAGE_LOCATION
        }
    }

}
