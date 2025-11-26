// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {OFTAdapterUpgradeable} from "@layerzerolabs/oft-evm-upgradeable/contracts/oft/OFTAdapterUpgradeable.sol";
import {IControllable, Controllable} from "../core/base/Controllable.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IStabilityOFTAdapter} from "../interfaces/IStabilityOFTAdapter.sol";
import {IOFTPausable} from "../interfaces/IOFTPausable.sol";
import {MessagingReceipt, MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

/// @notice Omnichain Fungible Token Adapter for exist STBL token
contract StabilityOFTAdapter is Controllable, OFTAdapterUpgradeable, IStabilityOFTAdapter {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    /// @notice Special compose message for xSTBL transfers between chains
    bytes32 internal constant COMPOSE_MESSAGE_XSTBL = keccak256(bytes("XSTBL"));

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.StabilityOFTAdapter")) - 1)) & ~bytes32(uint(0xff));
    bytes32 internal constant STABILITY_OFT_ADAPTER_STORAGE_LOCATION =
        0xc2fe35575ba2043e2e48d6fdb6b1fc90678ceafd17da235789a1487ce75a9a00;

    /// @custom:storage-location erc7201:stability.StabilityOFTAdapter
    struct StabilityOftAdapterStorage {
        /// @notice Paused state for addresses
        mapping(address => bool) paused;
    }

    bytes32 internal transient _currentComposeMsg;

    /// @notice Special message "XTBL" can be send through {sendXSTBL} only
    error ComposeMsgReserved();

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

    //region --------------------------------- XSTBL
    /// @notice Sends xSTBL to another chain
    /// @dev The user must send enough native tokens to cover the cross-chain message fees. Use quoteSend to estimate it.
    /// @param dstEid_ The target chain endpoint ID
    /// @param amount The amount of xSTBL to send
    /// @param msgFee The messaging fee struct obtained from quoteSend
    /// @param options Additional options for the transfer (gas limit on target chain, etc.)
    /// Use OptionsBuilder.addExecutorLzReceiveOption() to build options.
    function sendXSTBL(uint32 dstEid_, uint amount, MessagingFee memory msgFee, bytes memory options) external payable {
        // todo whitelisted only

        SendParam memory sendParam = SendParam({
            dstEid: dstEid_,
            to: bytes32(uint(uint160(msg.sender))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: COMPOSE_MESSAGE_XSTBL,
            oftCmd: ""
        });


        if (msgFee.lzTokenFee != 0) {
            // todo do we need to handle ZRO payments?
        }

        // @dev Set _currentComposeMsg for special logic in _debit and _send
        _currentComposeMsg = COMPOSE_MESSAGE_XSTBL;

        super.send{value: msg.value}(sendParam, msgFee, msg.sender);

        // @dev Clear _currentComposeMsg
        _currentComposeMsg = bytes32(0);
    }

    /// @notice Quote the gas needed to pay for sendimg {amount} of xSTBL to given target chain.
    /// @param dstEid_ Destination chain endpoint ID, see https://docs.layerzero.network/v2/concepts/glossary#endpoint-id
    /// @param options_ Additional options for the message. Use OptionsBuilder.addExecutorLzReceiveOption()
    /// @param payInLzToken_ Whether to return fee in ZRO token.
    /// @return fee A `MessagingFee` struct containing the calculated gas fee in either the native token or ZRO token.
    function quoteSendXSTBL(uint32 dstEid_, uint amount, bytes memory options, bool payInLzToken_) external view returns (MessagingFee memory msgFee) {
        SendParam memory sendParam = SendParam({
            dstEid: dstEid_,
            to: bytes32(uint(uint160(msg.sender))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: COMPOSE_MESSAGE_XSTBL,
            oftCmd: ""
        });
        return this.quoteSend(sendParam, false);

    }
    //endregion --------------------------------- XSTBL

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

        if (_currentComposeMsg == COMPOSE_MESSAGE_XSTBL) {
            // todo unstake STBL from xSTBL without penalty

            (amountSentLD, amountReceivedLD) = _debitView(amountLD_, minAmountLD_, dstEid_);
        } else {
            (amountSentLD, amountReceivedLD) = super._debit(from_, amountLD_, minAmountLD_, dstEid_);
        }
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

    /// @dev Ensure that compose message
    function _send(
        SendParam calldata _sendParam,
        MessagingFee calldata _fee,
        address _refundAddress
    ) internal virtual override returns (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) {
        if (_currentComposeMsg != COMPOSE_MESSAGE_XSTBL) {
            require(
                _sendParams.composeMsg.length == 0 || keccak256(_sendParams.composeMsg) != COMPOSE_MESSAGE_XSTBL, ComposeMsgReserved()
            );
        }
        return super._send(_sendParam, _fee, _refundAddress);
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
