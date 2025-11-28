// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library BridgeTokenLib {
    /// @notice Message from XTokenBridge:
    /// stake received STBL to xSTBL for the user, address of the user is passed as BridgeTokenMessage.data
    uint16 public constant MESSAGE_KIND_STAKE_XSTBL = 1;

    /// @notice Message to send through the bridge together with the token transfer
    struct BridgeTokenComposeMessage {
        /// @notice Address of the message receiver contract on destination chain
        /// Bridge checks only that the receiver is allowed,
        /// the actual logic of processing message must be implemented in the receiver contract
        address receiver;

        /// @notice Message data (content depends on actual receiver)
        bytes data;
    }

    //region --------------------------------- Main logic
    function makeRouteKey(uint32 srcEid_, address srcAddress_) internal pure returns (bytes32) {
        return bytes32(uint256(uint32(srcEid_)) << 224 | uint256(uint160(srcAddress_)));
    }

    /// @notice Decode BridgeTokenMessage from encoded bytes
    /// @param encodedMessage_ Encoded BridgeTokenMessage
    function decodeBridgeTokenComposeMessage(bytes memory encodedMessage_) internal pure returns (BridgeTokenComposeMessage memory) {
        return abi.decode(encodedMessage_, (BridgeTokenComposeMessage));
    }
    //endregion --------------------------------- Main logic

    //region --------------------------------- XTokenBridge Message Kind 1
    /// @notice Pack message of kind MESSAGE_KIND_XTOKEN_BRIDGE_1
    /// @param user_ Address of the user to stake received STBL for
    /// @param destXTokenBridge_ Address of the destination XTokenBridge
    function packComposeMessageKind1(address user_, address destXTokenBridge_) internal pure returns (bytes memory) {
        BridgeTokenComposeMessage memory message = BridgeTokenComposeMessage({
            receiver: destXTokenBridge_,
            data: abi.encodePacked(MESSAGE_KIND_STAKE_XSTBL, user_)
        });
        return abi.encode(message);
    }

    function decodeComposeMessageDataKind1(bytes memory data_) internal pure returns (uint16 kind, address user) {
        (kind, user) = abi.decode(data_, (uint16, address));
    }
    //endregion --------------------------------- XTokenBridge Message Kind 1
}