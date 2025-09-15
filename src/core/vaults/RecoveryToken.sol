// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Controllable, IControllable, IPlatform} from "../base/Controllable.sol";
import {ERC20Upgradeable, IERC20Metadata} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {IRecoveryToken} from "../../interfaces/IRecoveryToken.sol";

/// @title Incident impact recovery token
/// @author Alien Deployer (https://github.com/a17)
contract RecoveryToken is Controllable, ERC20Upgradeable, ERC20BurnableUpgradeable, IRecoveryToken {
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
        mapping(address account => bool paused) pausedAccounts;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    modifier onlyTarget() virtual {
        _requireTarget();
        _;
    }

    modifier onlyTargetOrMultisig() virtual {
        _requireTargetOrMultisig();
        _;
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

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRecoveryToken
    function mint(address account, uint amount) external onlyTarget {
        _mint(account, amount);
    }

    /// @inheritdoc IRecoveryToken
    function setAddressPaused(address account, bool paused_) external onlyTargetOrMultisig {
        RecoveryTokenStorage storage $ = _getRecoveryTokenStorage();
        $.pausedAccounts[account] = paused_;
        emit AccountPaused(account, paused_);
    }

    /// @inheritdoc IRecoveryToken
    function bulkTransferFrom(
        address from,
        address[] calldata to,
        uint[] calldata amounts
    ) external onlyGovernanceOrMultisig {
        uint len = to.length;
        require(len == amounts.length && len != 0, IControllable.IncorrectArrayLength());
        RecoveryTokenStorage storage $ = _getRecoveryTokenStorage();
        bool wasPaused = $.pausedAccounts[from];
        if (wasPaused) {
            $.pausedAccounts[from] = false;
        }
        for (uint i; i < len; ++i) {
            _transfer(from, to[i], amounts[i]);
        }
        if (wasPaused) {
            $.pausedAccounts[from] = true;
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERC20 HOOKS                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _update(address from, address to, uint value) internal override {
        RecoveryTokenStorage storage $ = _getRecoveryTokenStorage();
        require($.pausedAccounts[from] == false, TransfersPausedForAccount(from));
        super._update(from, to, value);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IRecoveryToken
    function target() public view returns (address) {
        return _getRecoveryTokenStorage().target;
    }

    /// @inheritdoc IRecoveryToken
    function paused(address account) public view returns (bool) {
        return _getRecoveryTokenStorage().pausedAccounts[account];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _requireTarget() internal view {
        require(_getRecoveryTokenStorage().target == msg.sender, IncorrectMsgSender());
    }

    function _requireTargetOrMultisig() internal view {
        address _target = _getRecoveryTokenStorage().target;
        address multisig = IPlatform(platform()).multisig();
        require(_target == msg.sender || multisig == msg.sender, IncorrectMsgSender());
    }

    function _getRecoveryTokenStorage() internal pure returns (RecoveryTokenStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _RECOVERY_TOKEN_STORAGE_LOCATION
        }
    }
}
