// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {OFTAdapterUpgradeable} from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTAdapterUpgradeable.sol";
import {IControllable, Controllable} from "../core/base/Controllable.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IStabilityOFTAdapter} from "../interfaces/IStabilityOFTAdapter.sol";
import {IOFTPausable} from "../interfaces/IOFTPausable.sol";

/// @notice Omnichain Fungible Token Adapter for exist STBL token
contract StabilityOFTAdapter is Controllable, OFTAdapterUpgradeable, IStabilityOFTAdapter {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.StabilityOFTAdapter")) - 1)) & ~bytes32(uint(0xff));
    bytes32 internal constant STABILITY_OFT_ADAPTER_STORAGE_LOCATION =
        0xc2fe35575ba2043e2e48d6fdb6b1fc90678ceafd17da235789a1487ce75a9a00;

    /// @custom:storage-location erc7201:stability.StabilityOFTAdapter
    struct StabilityOftAdapterStorage {
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

    /// @inheritdoc IStabilityOFTAdapter
    function initialize(address platform_) public initializer {
        address _delegate = IPlatform(platform_).multisig();

        __Controllable_init(platform_);
        __OFTAdapter_init(_delegate);
        __Ownable_init(_delegate);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         VIEW                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IOFTPausable
    function paused(address account_) external view returns (bool) {
        return getStabilityOftAdapterStorage().paused[account_];
    }

    //endregion --------------------------------- Initializers and view

    //region --------------------------------- Restricted actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                  RESTRICTED ACTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IOFTPausable
    function setPaused(address account, bool paused_) external onlyOperator {
        StabilityOftAdapterStorage storage $ = getStabilityOftAdapterStorage();
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
    function getStabilityOftAdapterStorage() internal pure returns (StabilityOftAdapterStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := STABILITY_OFT_ADAPTER_STORAGE_LOCATION
        }
    }

    function _requireNotPaused(address account) internal view {
        StabilityOftAdapterStorage storage $ = getStabilityOftAdapterStorage();
        require(!$.paused[account], IOFTPausable.Paused());
    }

    //endregion --------------------------------- Internal logic
}
