// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IOAppComposer} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
import {IControllable, Controllable} from "../core/base/Controllable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOFTPausable} from "../interfaces/IOFTPausable.sol";
import {IXSTBL} from "../interfaces/IXSTBL.sol";
import {IXTokenBridge} from "../interfaces/IXTokenBridge.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SendParam, MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

contract XTokenBridge is Controllable, IXTokenBridge, IOAppComposer {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.XTokenBridge")) - 1)) & ~bytes32(uint(0xff));
    bytes32 internal constant XOKEN_BRIDGE_STORAGE_LOCATION =
        0x7331a1638fe957f8dc3395f52254374f52b3cbbdf185d4405a764a49dfb7f400;

    /// @notice LayerZero v2 Endpoint address
    address public immutable LZ_ENDPOINT;

    //region --------------------------------- Data types
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         Data types                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.XTokenBridge
    struct XTokenBridgeStorage {
        /// @notice LayerZero Omnichain Fungible Token (OFT) bridge address
        address bridge;

        /// @notice Optional: LayerZero ZRO token address to pay fees in ZRO, see endpoint.lzToken()
        address lzToken;

        /// @notice xSTBL address
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
    function quoteSend(
        uint32 dstEid_,
        uint amount,
        bytes memory options,
        bool payInLzToken_
    ) external view returns (MessagingFee memory msgFee) {
        XTokenBridgeStorage storage $ = _getStorage();

        address receiver = $.xTokenBridges[dstEid_];

        SendParam memory sendParam = SendParam({
            dstEid: dstEid_,
            to: bytes32(uint(uint160(receiver))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: abi.encode(msg.sender),
            oftCmd: ""
        });
        return IOFTPausable($.bridge).quoteSend(sendParam, payInLzToken_);
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
    }

    /// @inheritdoc IXTokenBridge
    function setLzToken(address lzToken_) external onlyOperator {
        XTokenBridgeStorage storage $ = _getStorage();
        $.lzToken = lzToken_;
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

        SendParam memory sendParam = SendParam({
            dstEid: dstEid_,
            to: bytes32(uint(uint160(receiver))),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: abi.encode(msg.sender),
            oftCmd: ""
        });

        IOFTPausable(_bridge).send{value: msgFee.nativeFee}(sendParam, msgFee, msg.sender);

        emit Send(msg.sender, dstEid_, amount);
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

    /// @notice Handles composed messages from the OFT: staking received STBL to xSTBL for the recipient
    /// @param oApp_ Address of the originating OApp (must be trusted OFT)
    /// param guid_ Unique identifier for this message
    /// @param message_ Encoded message containing compose data
    function lzCompose(
        address oApp_,
        bytes32,
        /*guid_*/
        bytes calldata message_,
        address,
        /*_executor*/
        bytes calldata /*_extraData*/
    ) external payable override {
        XTokenBridgeStorage storage $ = _getStorage();
        address _bridge = $.bridge;

        // ---------------- Verify the message source
        require(msg.sender == LZ_ENDPOINT, UnauthorizedSender());
        require(oApp_ == _bridge, UntrustedOApp());

        uint32 srcEid = OFTComposeMsgCodec.srcEid(message_);
        {
            bytes32 composeFromBytes = OFTComposeMsgCodec.composeFrom(message_);
            // @dev original sender who initiated the OFT transfer
            address originalSender = OFTComposeMsgCodec.bytes32ToAddress(composeFromBytes);
            require($.xTokenBridges[srcEid] == originalSender, InvalidOriginalSender());
        }

        // ---------------- Decode the message
        uint amountLD = OFTComposeMsgCodec.amountLD(message_);
        address recipient = abi.decode(OFTComposeMsgCodec.composeMsg(message_), (address));

        // ---------------- state STBL for the user
        IERC20(IXSTBL($.xToken).STBL()).forceApprove($.xToken, amountLD);
        IXSTBL($.xToken).takeFromBridge(recipient, amountLD);

        emit Staked(recipient, srcEid, amountLD);
    }

    //endregion --------------------------------- IOAppComposer

    //region --------------------------------- Internal utils
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     Internal utils                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getStorage() internal pure returns (XTokenBridgeStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := XOKEN_BRIDGE_STORAGE_LOCATION
        }
    }

    //endregion --------------------------------- Internal utils
}
