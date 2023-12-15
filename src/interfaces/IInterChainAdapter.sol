// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title Interoperability adapter
/// @author Alien Deployer (https://github.com/a17)
interface IInterChainAdapter {
    /// @dev Message to be sent from one blockchain to another
    struct Message {
        bytes32 action;
        uint64 chainFrom;
        uint64 chainTo;
        bytes32[3] extraPayload;
        address[] addresses;
        uint[] numbers;
    }

    /// @notice String ID of the adapter
    function interChainAdapterId() external returns (string memory);

    /// @notice Inter-chain protocol endpoint
    /// @return Address of endpoint
    function endpoint() external view returns (address);

    /// @notice Send message to other blockchain
    function sendMessage(Message memory message) external;
}
