// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

interface IXTokenBridge {
    /// @notice Emitted when user sends xToken to another chain
    /// @param userFrom The address of the user-sender
    /// @param dstEid The destination chain endpoint ID
    /// @param amount The amount of xToken to send (local decimals).
    /// @param amountSentLD Amount of tokens ACTUALLY debited from the sender in local decimals (from OFTReceipt)
    /// @param guidId The unique GUID identifier for the sent message (from MessagingReceipt)
    /// @param nonce The nonce of the sent message (from MessagingReceipt)
    /// @param nativeFee The amount of native fee paid for the cross-chain message
    event XTokenSent(
        address indexed userFrom,
        uint32 indexed dstEid,
        uint amount,
        uint amountSentLD,
        bytes32 indexed guidId,
        uint64 nonce,
        uint nativeFee
    );

    /// @notice Emitted when xToken is received from another chain
    /// @param userTo The address of the recipient-user
    /// @param srcEid The source chain endpoint ID
    /// @param amount The amount of xToken received
    /// @param guidId The unique GUID identifier for the received message
    event Staked(address indexed userTo, uint32 indexed srcEid, uint amount, bytes32 guidId);

    event SetXTokenBridges(uint32[] dstEids, address[] xTokenBridges);

    error NotBridge();
    error ChainNotSupported();
    error IncorrectAmountReceivedFromXToken();
    error InvalidSenderXTokenBridge();
    error IncorrectReceiver();
    error UnauthorizedSender();
    error UntrustedOApp();
    error SenderPaused();
    error ZeroAmount();
    error IncorrectNativeValue();

    /// @notice LayerZero Omnichain Fungible Token (OFT) bridge address
    function bridge() external view returns (address);

    /// @notice xSTBL address
    function xToken() external view returns (address);

    /// @notice Get the xTokenBridge address for the given destination chain
    /// @param dstEid_ Destination chain endpoint ID
    function xTokenBridge(uint32 dstEid_) external view returns (address);

    /// @notice Quote the gas needed to pay for sending `amount` of xSTBL to given target chain.
    /// Paying using ZRO token (Layer Zero token) is not supported.
    /// @param dstEid_ Destination chain endpoint ID
    /// @param amount Amount of tokens to send (local decimals)
    /// @param options Additional options for the message. Use:
    ///    OptionsBuilder.addExecutorLzReceiveOption()
    ///    OptionsBuilder.addExecutorLzComposeOption()
    /// Gas limit should take into account two calls on the destination chain: lzReceive() and lzCompose()
    /// @return msgFee A `MessagingFee` struct containing the calculated gas fee.
    function quoteSend(
        uint32 dstEid_,
        uint amount,
        bytes calldata options
    ) external view returns (MessagingFee memory msgFee);

    /// @notice Initialize the XTokenBridge
    /// @param platform_ Address of the platform contract
    /// @param bridge_ Address of the LayerZero OFT bridge contract
    /// @param xToken_ Address of the xSTBL token contract
    function initialize(address platform_, address bridge_, address xToken_) external;

    /// @notice Sets the xTokenBridge address for the given destination chain
    /// @param dstEids_ Destination chain endpoint IDs
    /// @param xTokenBridges_ Addresses of the xTokenBridge on the destination chain
    function setXTokenBridge(uint32[] memory dstEids_, address[] memory xTokenBridges_) external;

    /// @notice Sends xToken to another chain
    /// @dev The user must send enough native tokens to cover the cross-chain message fees. Use quoteSend to estimate it.
    /// @param dstEid_ The target chain endpoint ID
    /// @param amount The amount of xToken to send (local decimals)
    /// @param msgFee The messaging fee struct obtained from quoteSend
    /// @param options Additional options for the transfer (gas limit on target chain, etc.)
    /// Use OptionsBuilder.addExecutorLzReceiveOption() to build options.
    /// Gas limit should take into account two calls on the destination chain: lzReceive() and lzCompose()
    function send(uint32 dstEid_, uint amount, MessagingFee calldata msgFee, bytes calldata options) external payable;

    /// @notice Salvage tokens mistakenly sent to this contract
    /// @param token Address of the token to salvage
    /// @param amount Amount of tokens to salvage
    /// @param receiver Address to send the salvaged tokens to
    function salvage(address token, uint amount, address receiver) external;
}
