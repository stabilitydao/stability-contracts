// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";

import {Controllable, IControllable} from "../base/Controllable.sol";
import {
    ERC20Upgradeable,
    IERC20,
    IERC20Metadata
} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IRecoveryToken} from "../../interfaces/IRecoveryToken.sol";

/// @title Incident impact recovery token
/// @author Alien Deployer (https://github.com/a17)
contract RecoveryToken is Controllable, ERC20Upgradeable, IRecoveryToken {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.RecoveryToken")) - 1)) & ~bytes32(uint(0xff));
    bytes32 private constant _RECOVERY_TOKEN_STORAGE_LOCATION =
        0x30fc22a82c56596b37919634e59000c1de8c9b7b97da0c427bd6d1477af44d00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.RecoveryToken
    struct RecoveryTokenStorage {
        address target;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRecoveryToken
    function initialize(address platform_, address target_) public initializer {
        __Controllable_init(platform_);
        __ERC20_init(
            string.concat("Recovery ", IERC20Metadata(target_).name()),
            string.concat("REC", IERC20Metadata(target_).symbol())
        );
        RecoveryTokenStorage storage $ = _getRecoveryTokenStorage();
        $.target = target_;
    }

    function mint(address account, uint amount) external {
        require(_getRecoveryTokenStorage().target == msg.sender, IncorrectMsgSender());
        _mint(account, amount);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRecoveryToken
    function target() public view returns (address) {
        return _getRecoveryTokenStorage().target;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getRecoveryTokenStorage() internal pure returns (RecoveryTokenStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _RECOVERY_TOKEN_STORAGE_LOCATION
        }
    }
}
