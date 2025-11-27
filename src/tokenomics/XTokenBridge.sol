// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Origin, ILayerZeroReceiver} from "../../lib/LayerZero-v2/packages/layerzero-v2/evm/protocol/contracts/interfaces/ILayerZeroReceiver.sol";
import {IControllable, Controllable} from "../core/base/Controllable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOFTPausable} from "../interfaces/IOFTPausable.sol";
import {IXSTBL} from "../interfaces/IXSTBL.sol";
import {IXTokenBridge} from "../interfaces/IXTokenBridge.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SendParam, MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

contract XTokenBridge is Controllable, IXTokenBridge, ILayerZeroReceiver {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    uint8 internal constant MESSAGE_KIND_1 = 1;

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.XSTBLBridge")) - 1)) & ~bytes32(uint(0xff));
    bytes32 internal constant XOKEN_BRIDGE_STORAGE_LOCATION = 0;

    //region --------------------------------- Data types
    /// @custom:storage-location erc7201:stability.XSTBLBridge
    struct XTokenBridgeStorage {
        /// @notice LayerZero Omnichain Fungible Token (OFT) bridge address
        address bridge;

        /// @notice Optional: LayerZero ZRO token address to pay fees in ZRO
        address lzToken;

        /// @notice xSTBL address
        address xToken;

        /// @notice xTokenBridge addresses for destination chains
        mapping(uint32 dstEid_ => address xTokenBridge) xTokenBridges;
    }

    /// @notice Message to send through the bridge together with the token transfer
    struct MessageData {
        /// @notice Message kind
        uint8 kind;

        /// @notice Owner of transferred tokens
        address user;
    }

    //endregion --------------------------------- Data types

    //region --------------------------------- Initializers

    /// @inheritdoc IXTokenBridge
    function initialize(address platform_, address bridge_, address lzToken_, address xToken_) public initializer {
        __Controllable_init(platform_);

        XTokenBridgeStorage storage $ = _getStorage();
        $.bridge = bridge_;
        $.lzToken = lzToken_;
        $.xToken = xToken_;
    }
    //endregion --------------------------------- Initializers

    //region --------------------------------- View

    /// @inheritdoc IXTokenBridge
    function bridge() external view returns (address) {
        XTokenBridgeStorage storage $ = _getStorage();
        return $.bridge;
    }

    /// @inheritdoc IXTokenBridge
    function lzToken() external view returns (address) {
        XTokenBridgeStorage storage $ = _getStorage();
        return $.lzToken;
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
    function quoteSend(uint32 dstEid_, uint amount, bytes memory options, bool payInLzToken_) external view returns (MessagingFee memory msgFee) {
        XTokenBridgeStorage storage $ = _getStorage();

        MessageData memory messageData = MessageData({
            kind: MESSAGE_KIND_1,
            user: msg.sender
        });

        SendParam memory sendParam = SendParam({
            dstEid: dstEid_,
            to: bytes32(uint(uint160($.xTokenBridges[dstEid_]))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: abi.encode(messageData),
            oftCmd: ""
        });
        return IOFTPausable($.bridge).quoteSend(sendParam, payInLzToken_);

    }

    //endregion --------------------------------- View

    //region --------------------------------- Actions
    /// @inheritdoc IXTokenBridge
    function setXTokenBridge(uint32 dstEid_, address bridge_) external onlyOperator {
        XTokenBridgeStorage storage $ = _getStorage();
        $.xTokenBridges[dstEid_] = bridge_;
    }

    /// @inheritdoc IXTokenBridge
    function send(uint32 dstEid_, uint amount, MessagingFee memory msgFee, bytes memory options) external payable {
        XTokenBridgeStorage storage $ = _getStorage();
        address _bridge = $.bridge;

        // ----------------- prepare STBL amount to send through the bridge
        /// @dev xSTBL
        address _xToken = $.xToken;

        /// @dev STBL
        address token = IXSTBL(_xToken).STBL();

        IXSTBL(_xToken).sendToBridge(msg.sender, amount);
        require(IERC20(token).balanceOf(address(this)) >= amount, InsufficientAmountReceived());

        IERC20(token).forceApprove(_bridge, amount);

        // ----------------- prepare ZRO fee if necessary
        if (msgFee.lzTokenFee != 0) {
            address _lzToken = $.lzToken;
            if (_lzToken == address(0)) {
                revert LzTokenFeeNotSupported();
            }
            IERC20(_lzToken).safeTransferFrom(msg.sender, address(this), msgFee.lzTokenFee);
            IERC20(_lzToken).forceApprove(_bridge, msgFee.lzTokenFee);
        }

        // ----------------- send STBL through the bridge
        /// @dev Receiver - address of this contract in another chain
        address receiver = $.xTokenBridges[dstEid_];
        require(receiver != address(0), ChainNotSupported());

        /// @dev Message for the receiver
        MessageData memory messageData = MessageData({
            kind: MESSAGE_KIND_1,
            user: msg.sender
        });

        SendParam memory sendParam = SendParam({
            dstEid: dstEid_,
            to: bytes32(uint(uint160(receiver))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: abi.encode(messageData),
            oftCmd: ""
        });

        IOFTPausable(_bridge).send(sendParam, msgFee, msg.sender);

        emit Send(msg.sender, dstEid_, amount);
    }
    //endregion --------------------------------- Actions

    //region --------------------------------- ILayerZeroReceiver

    function allowInitializePath(Origin calldata origin) external view returns (bool) {
        return _getStorage().xTokenBridges[origin.srcEid] != address(0);
    }

    function nextNonce(uint32, bytes32) external pure returns (uint64) {
        return 0; // stateless implementation
    }

    function lzReceive(
        Origin calldata origin,
        bytes32 /*guid*/,
        bytes calldata message,
        address /*caller*/,
        bytes calldata /*extraData*/
    ) external payable {
        XTokenBridgeStorage storage $ = _getStorage();

        require(msg.sender == $.bridge, NotBridge());
        require($.xTokenBridges[origin.srcEid] != address(0), BadSourceChain());

        // ----------------- Decode and check incoming message
        // message = abi.encode(amountLD, composeMsg)
        (uint256 amountLD, bytes memory composeMsg) = abi.decode(message, (uint256, bytes));
        MessageData memory data = abi.decode(composeMsg, (MessageData));

        require(data.kind == MESSAGE_KIND_1, InvalidMessageFormat());

        // ----------------- Stake received STBL to xSTBL for the user
        address _xToken = $.xToken;
        address token = IXSTBL(_xToken).STBL();
        require(IERC20(token).balanceOf(address(this)) >= amountLD, InsufficientAmountReceived());
        IXSTBL(_xToken).receiveFromBridge(data.user, amountLD);

        emit Receive(data.user, origin.srcEid, amountLD);
    }

    //endregion --------------------------------- ILayerZeroReceiver

    //region --------------------------------- Internal utils

    function _getStorage() internal pure returns (XTokenBridgeStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := XOKEN_BRIDGE_STORAGE_LOCATION
        }
    }

    //endregion --------------------------------- Internal utils
}