// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {OFTAdapterUpgradeable} from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTAdapterUpgradeable.sol";
import {IControllable, Controllable} from "../core/base/Controllable.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {ITokenOFTAdapter} from "../interfaces/ITokenOFTAdapter.sol";
import {IOFTPausable} from "../interfaces/IOFTPausable.sol";

/// @notice Omnichain Fungible Token Adapter for exist main-token
contract TokenOFTAdapter is Controllable, OFTAdapterUpgradeable, ITokenOFTAdapter {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.TokenOFTAdapter")) - 1)) & ~bytes32(uint(0xff));
    bytes32 internal constant TOKEN_OFT_ADAPTER_STORAGE_LOCATION =
        0xa644c5e388c18df754c7a15986d33976363be2bae99e7e86772378f965c5c200;

    /// @custom:storage-location erc7201:stability.TokenOFTAdapter
    struct TokenOftAdapterStorage {
        /// @notice Paused state for addresses
        mapping(address => bool) paused;
    }

    //region --------------------------------- Initializers and view
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    constructor(address token_, address lzEndpoint_) OFTAdapterUpgradeable(token_, lzEndpoint_) {
        _disableInitializers();
    }

    /// @inheritdoc ITokenOFTAdapter
    function initialize(address platform_, address delegate_) public initializer {
        address _owner = IPlatform(platform_).multisig();

        __Controllable_init(platform_);
        __OApp_init(delegate_ == address(0) ? _owner : delegate_);
        __Ownable_init(_owner);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         VIEW                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IOFTPausable
    function paused(address account_) external view returns (bool) {
        return getTokenOftAdapterStorage().paused[account_];
    }

    //endregion --------------------------------- Initializers and view

    //region --------------------------------- Restricted actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  RESTRICTED ACTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IOFTPausable
    function setPaused(address account, bool paused_) external onlyOperator {
        TokenOftAdapterStorage storage $ = getTokenOftAdapterStorage();
        $.paused[account] = paused_;

        emit Pause(account, paused_);
    }

    //endregion --------------------------------- Restricted actions

    //region --------------------------------- Overrides
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  OVERRIDES                                 */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    function _checkOwner() internal view override {
        _requireMultisig();
    }

    /// @dev Paused accounts cannot send tokens
    function _debit(
        address from_,
        uint amountLD_,
        uint minAmountLD_,
        uint32 dstEid_
    ) internal virtual override returns (uint amountSentLD, uint amountReceivedLD) {
        _requireNotPaused(from_);

        return super._debit(from_, amountLD_, minAmountLD_, dstEid_);
    }

    /// @dev Paused accounts cannot receive tokens
    function _credit(
        address to_,
        uint amountLD_,
        uint32 srcEid_
    ) internal virtual override returns (uint amountReceivedLD) {
        _requireNotPaused(to_);

        return super._credit(to_, amountLD_, srcEid_);
    }

    //endregion --------------------------------- Overrides

    //region --------------------------------- Internal logic
    function getTokenOftAdapterStorage() internal pure returns (TokenOftAdapterStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := TOKEN_OFT_ADAPTER_STORAGE_LOCATION
        }
    }

    function _requireNotPaused(address account) internal view {
        TokenOftAdapterStorage storage $ = getTokenOftAdapterStorage();
        require(!$.paused[account] && !$.paused[address(this)], Paused());
    }

    //endregion --------------------------------- Internal logic
}
