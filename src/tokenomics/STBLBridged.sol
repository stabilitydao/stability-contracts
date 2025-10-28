// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {OFTUpgradeable} from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTUpgradeable.sol";
import {IControllable, Controllable} from "../core/base/Controllable.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";

/// @notice Omnichain Fungible Token - bridged version of STBL token from Sonic to other chains
contract STBLBridged is Controllable, OFTUpgradeable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.STBLBridged")) - 1)) & ~bytes32(uint(0xff));
    bytes32 internal constant _STBL_BRIDGED_STORAGE_LOCATION =
        0x4ff2e3a08d98d9373e37265d0e0506d7c0c57521cd81ce2fe040c768fe146b00;

    /// @custom:storage-location erc7201:stability.STBLBridged
    struct StblBridgedStorage {
        /// @notice Paused state for addresses
        mapping(address => bool) paused;
    }

    error Paused();

    event Pause(address indexed account, bool paused);

    //region --------------------------------- Initializers
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor(address lzEndpoint_) OFTUpgradeable(lzEndpoint_) {
        _disableInitializers();
    }

    function initialize(address platform_, string memory _name, string memory _symbol) public initializer {
        address _delegate = IPlatform(platform_).multisig(); // todo

        __Controllable_init(platform_);
        __OFT_init(_name, _symbol, _delegate);
        __Ownable_init(_delegate);
    }
    //endregion --------------------------------- Initializers

    //region --------------------------------- Restricted actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  RESTRICTED ACTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function setPaused(address account, bool paused_) external onlyOperator {
        StblBridgedStorage storage $ = getSTBLBridgedStorage();
        $.paused[account] = paused_;

        emit Pause(account, paused_);
    }

    //endregion --------------------------------- Restricted actions

    //region --------------------------------- Overrides
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  OVERRIDES                                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function _checkOwner() internal view override {
        _requireGovernanceOrMultisig(); // todo
    }

    /// @dev Paused accounts cannot send tokens
    function _update(address from, address to, uint value) internal virtual override {
        _requireNotPaused(from);

        super._update(from, to, value);
    }

    //endregion --------------------------------- Overrides

    //region --------------------------------- Internal logic
    function getSTBLBridgedStorage() internal pure returns (StblBridgedStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _STBL_BRIDGED_STORAGE_LOCATION
        }
    }

    function _requireNotPaused(address account) internal view {
        StblBridgedStorage storage $ = getSTBLBridgedStorage();
        require(!$.paused[account], Paused());
    }

    //endregion --------------------------------- Internal logic
}
