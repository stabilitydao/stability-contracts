// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

interface IXTokenBridge {
    /// @notice Emitted when user initiated cross-chain send
    event Send(address indexed from, uint32 indexed dstEid, uint amount);
    event Receive(address indexed to, uint32 indexed srcEid, uint amount);

    error NotBridge();
    error LzTokenFeeNotSupported();
    error ChainNotSupported();
    error InsufficientAmountReceived();
    error InvalidMessageFormat();
    error IncorrectReceiver();
    error UnauthorizedSender();
    error UntrustedOApp();

    /// @notice LayerZero Omnichain Fungible Token (OFT) bridge address
    function bridge() external view returns (address);

    /// @notice Optional: LayerZero ZRO token address to pay fees in ZRO
    function lzToken() external view returns (address);

    /// @notice xSTBL address
    function xToken() external view returns (address);

    /// @notice Get the xTokenBridge address for the given destination chain
    /// @param dstEid_ Destination chain endpoint ID
    function xTokenBridge(uint32 dstEid_) external view returns (address);

    /// @notice Quote the gas needed to pay for sending `amount` of xSTBL to given target chain.
    /// @param dstEid_ Destination chain endpoint ID
    /// @param amount Amount of tokens to send (local decimals)
    /// @param options Additional options for the message (use OptionsBuilder.addExecutorLzReceiveOption())
    /// @param payInLzToken_ Whether to return fee in ZRO token.
    /// @return msgFee A `MessagingFee` struct containing the calculated gas fee.
    function quoteSend(
        uint32 dstEid_,
        uint amount,
        bytes calldata options,
        bool payInLzToken_
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

    /// @notice Sets the LayerZero ZRO token address to pay fees in ZRO, see endpoint.lzToken()
    /// @param lzToken_ Address of the LayerZero ZRO token contract. Fee in ZRO is forbidden if 0
    function setLzToken(address lzToken_) external;

    /// @notice Sends xToken to another chain
    /// @dev The user must send enough native tokens to cover the cross-chain message fees. Use quoteSend to estimate it.
    /// @param dstEid_ The target chain endpoint ID
    /// @param amount The amount of xToken to send (local decimals)
    /// @param msgFee The messaging fee struct obtained from quoteSend
    /// @param options Additional options for the transfer (gas limit on target chain, etc.)
    /// Use OptionsBuilder.addExecutorLzReceiveOption() to build options.
    function send(
        uint32 dstEid_,
        uint amount,
        MessagingFee calldata msgFee,
        bytes calldata options
    ) external payable;
}
