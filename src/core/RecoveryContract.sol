// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Controllable, IControllable, IPlatform} from "./base/Controllable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {
ERC20Upgradeable,
IERC20,
IERC20Metadata
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from
"@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {IRecoveryContract} from "../interfaces/IRecoveryContract.sol";

/// @title Recovery contract to swap assets on recovery tokens in recovery pools
/// @author dvpublic (https://github.com/dvpublic)
/// Changelog:
contract RecoveryContract is Controllable, IRecoveryContract {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.1.0";

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.RecoveryContract")) - 1)) & ~bytes32(uint(0xff));
    bytes32 private constant _RECOVERY_CONTRACT_STORAGE_LOCATION = 0x0; // todo

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.RecoveryContract
    struct RecoveryContractStorage {

        /// @notice UniswapV3 pools with recovery tokens
        EnumerableSet.AddressSet recoveryPools;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRecoveryContract
    function initialize(address platform_) public initializer {
        __Controllable_init(platform_);
        RecoveryContractStorage storage $ = _getRecoveryTokenStorage();
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
    function _getRecoveryTokenStorage() internal pure returns (RecoveryContractStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _RECOVERY_CONTRACT_STORAGE_LOCATION
        }
    }

}
