// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IOAppComposer} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import {IControllable, Controllable} from "../core/base/Controllable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOFTPausable} from "../interfaces/IOFTPausable.sol";
import {IXToken} from "../interfaces/IXToken.sol";
import {IXTokenBridge} from "../interfaces/IXTokenBridge.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SendParam, MessagingFee, OFTReceipt} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {MessagingReceipt} from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

/// @notice XTokenBridge - bridge for xToken (i.e. xSTBL) using LayerZero Omnichain Fungible Token (OFT) bridge
/// Changelog:
///  - 1.0.2: Fix Staked event (indexed guid)
///  - 1.0.1: Add buildOptions function
contract XTokenBridge is Controllable, IXTokenBridge, IOAppComposer, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using OptionsBuilder for bytes;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.1";

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.XTokenBridge")) - 1)) & ~bytes32(uint(0xff));
    bytes32 internal constant XTOKEN_BRIDGE_STORAGE_LOCATION =
        0x7331a1638fe957f8dc3395f52254374f52b3cbbdf185d4405a764a49dfb7f400;

    /// @notice LayerZero v2 Endpoint address
    /// slither-disable-next-line naming-convention
    address public immutable LZ_ENDPOINT;

    //region --------------------------------- Data types
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         Data types                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.XTokenBridge
    struct XTokenBridgeStorage {
        /// @notice LayerZero Omnichain Fungible Token (OFT) bridge address
        address bridge;

        /// @notice xToken address
        address xToken;

        /// @notice xTokenBridge addresses for destination chains
        mapping(uint32 dstEid_ => address xTokenBridge) xTokenBridges;
    }

    //endregion --------------------------------- Data types

    //region --------------------------------- Initializers
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      Initializers                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    constructor(address lzEndpoint_) {
        LZ_ENDPOINT = lzEndpoint_;
    }

    /// @inheritdoc IXTokenBridge
    function initialize(address platform_, address bridge_, address xToken_) public initializer {
        __Controllable_init(platform_);

        XTokenBridgeStorage storage $ = _getStorage();
        $.bridge = bridge_;
        $.xToken = xToken_;
        // lzToken is zero by default
    }

    //endregion --------------------------------- Initializers

    //region --------------------------------- View
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                            View                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IXTokenBridge
    function bridge() external view returns (address) {
        XTokenBridgeStorage storage $ = _getStorage();
        return $.bridge;
    }

    /// @inheritdoc IXTokenBridge
    function xToken() external view returns (address) {
        XTokenBridgeStorage storage $ = _getStorage();
        return $.xToken;
    }

    /// @inheritdoc IXTokenBridge
    function xTokenBridge(uint32 dstEid_) external view returns (address) {
        XTokenBridgeStorage storage $ = _getStorage();
        return $.xTokenBridges[dstEid_];
    }

    /// @inheritdoc IXTokenBridge
    function quoteSend(
        uint32 dstEid_,
        uint amount,
        bytes memory options
    ) external view returns (MessagingFee memory msgFee) {
        XTokenBridgeStorage storage $ = _getStorage();

        /// @dev Receiver - address of this contract in another chain
        address receiver = $.xTokenBridges[dstEid_];

        SendParam memory sendParam = SendParam({
            dstEid: dstEid_,
            to: bytes32(uint(uint160(receiver))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            /// @dev ComposeMsg contains an address of the original user who initiated the transfer
            composeMsg: abi.encode(msg.sender),
            oftCmd: ""
        });

        // paying using ZRO token (Layer Zero token) is not supported
        return IOFTPausable($.bridge).quoteSend(sendParam, false);
    }

    /// @inheritdoc IXTokenBridge
    function buildOptions(
        uint128 gasLzReceive_,
        uint128 valueLzReceive_,
        uint16 _indexLzCompose,
        uint128 gasLzCompose,
        uint128 valueLzCompose_
    ) external pure returns (bytes memory) {
        return OptionsBuilder.newOptions().addExecutorLzReceiveOption(gasLzReceive_, valueLzReceive_)
            .addExecutorLzComposeOption(_indexLzCompose, gasLzCompose, valueLzCompose_);
    }

    //endregion --------------------------------- View

    //region --------------------------------- Actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          Actions                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IXTokenBridge
    function setXTokenBridge(
        uint32[] memory dstEids_,
        address[] memory xTokenBridges_
    ) external onlyGovernanceOrMultisig {
        XTokenBridgeStorage storage $ = _getStorage();
        uint len = dstEids_.length;
        require(len == xTokenBridges_.length, IControllable.IncorrectArrayLength());

        for (uint i; i < len; ++i) {
            $.xTokenBridges[dstEids_[i]] = xTokenBridges_[i];
        }

        emit SetXTokenBridges(dstEids_, xTokenBridges_);
    }

    /// @inheritdoc IXTokenBridge
    function send(
        uint32 dstEid_,
        uint amount,
        MessagingFee memory msgFee,
        bytes memory options
    ) external payable nonReentrant {
        XTokenBridgeStorage storage $ = _getStorage();
        address _bridge = $.bridge;

        // ----------------- check amount and value
        require(amount != 0, ZeroAmount());
        /// @dev exact value must be sent otherwise excess will leave stuck in the contract
        require(msg.value == msgFee.nativeFee, IncorrectNativeValue());

        // ----------------- ensure that sender is not paused (the bridge is not able to check it on its own)
        require(!IOFTPausable(_bridge).paused(msg.sender), SenderPaused());

        // ----------------- prepare main-token amount to send through the bridge
        address _xToken = $.xToken;

        /// @dev main-token address (STBL)
        address token = IXToken(_xToken).token();

        {
            IXToken(_xToken).sendToBridge(msg.sender, amount);
            require(IERC20(token).balanceOf(address(this)) >= amount, IncorrectAmountReceivedFromXToken());
        }

        IERC20(token).forceApprove(_bridge, amount);

        // ----------------- send main-token through the bridge
        /// @dev Receiver - address of this contract in another chain
        address receiver = $.xTokenBridges[dstEid_];
        require(receiver != address(0), ChainNotSupported());

        SendParam memory sendParam = SendParam({
            dstEid: dstEid_,
            to: bytes32(uint(uint160(receiver))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            /// @dev ComposeMsg contains an address of the original user who initiated the transfer
            composeMsg: abi.encode(msg.sender),
            oftCmd: ""
        });

        (MessagingReceipt memory r, OFTReceipt memory oftReceipt) =
            IOFTPausable(_bridge).send{value: msgFee.nativeFee}(sendParam, msgFee, msg.sender);

        emit XTokenSent(msg.sender, dstEid_, amount, oftReceipt.amountSentLD, r.guid, r.nonce, r.fee.nativeFee);
    }

    /// @inheritdoc IXTokenBridge
    function salvage(address token, uint amount, address receiver) external onlyGovernanceOrMultisig {
        if (amount == 0) {
            amount = IERC20(token).balanceOf(address(this));
        }
        IERC20(token).safeTransfer(receiver, amount);
    }

    //endregion --------------------------------- Actions

    //region --------------------------------- IOAppComposer
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     IOAppComposer                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Handles composed messages from the OFT: staking received main-token to xToken for the recipient
    /// @param oApp_ Address of the originating OApp (must be trusted OFT)
    /// @param guid_ Unique identifier for this message
    /// @param message_ Encoded message containing compose data.
    /// The message is generated inside OFT-adapter.lzReceive on destination chain.
    function lzCompose(
        address oApp_,
        bytes32 guid_,
        bytes calldata message_,
        address,
        /*_executor*/
        bytes calldata /*_extraData*/
    ) external payable override nonReentrant {
        XTokenBridgeStorage storage $ = _getStorage();
        address _bridge = $.bridge;

        // ---------------- Verify the message source
        require(msg.sender == LZ_ENDPOINT, UnauthorizedSender());
        require(oApp_ == _bridge, UntrustedOApp());

        uint32 srcEid = OFTComposeMsgCodec.srcEid(message_);
        {
            bytes32 composeFromBytes = OFTComposeMsgCodec.composeFrom(message_);
            /// @dev an instance of xTokenBridges which initiated the OFT transfer
            address senderXTokenBridge = OFTComposeMsgCodec.bytes32ToAddress(composeFromBytes);
            require($.xTokenBridges[srcEid] == senderXTokenBridge, InvalidSenderXTokenBridge());
        }

        // ---------------- Decode the message
        uint amountLD = OFTComposeMsgCodec.amountLD(message_);
        address recipient = abi.decode(OFTComposeMsgCodec.composeMsg(message_), (address));

        require(recipient != address(0), IncorrectReceiver()); // just for safety
        require(amountLD != 0, ZeroAmount()); // just for safety

        // ---------------- stake main-token for the user
        IERC20(IXToken($.xToken).token()).forceApprove($.xToken, amountLD);
        IXToken($.xToken).takeFromBridge(recipient, amountLD);
        // we don't check result user balance here to reduce gas consumption

        emit Staked(recipient, srcEid, amountLD, guid_);
    }

    //endregion --------------------------------- IOAppComposer

    //region --------------------------------- Internal utils
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Internal utils                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getStorage() internal pure returns (XTokenBridgeStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := XTOKEN_BRIDGE_STORAGE_LOCATION
        }
    }

    //endregion --------------------------------- Internal utils
}
