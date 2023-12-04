// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title Stability Bridge
/// @author Alien Deployer (https://github.com/a17)
interface IBridge {
    struct Link {
        /// @dev Sorted chain A (chain A < chain B)
        uint16 chainA;
        /// @dev Sorted chain B
        uint16 chainB;
        /// @dev Address of Bridge contract in chain A
        address bridgeA;
        /// @dev Address of Bridge contract in chain B
        address bridgeB;
        /// @dev String IDs of inter-chain adapters supported for this route. Not used in link hash calculation.
        string[] interChainAdapterId;
    }

    /// @notice Current chain ID
    function chainId() external view returns (uint16);

    /// @notice Get link
    /// @param linkHash Hash of link string ID
    /// @return Link data
    function link(bytes32 linkHash) external view returns (Link memory);

    /// @notice All links in the Bridge (in current chain)
    /// @return Links data
    function links() external view returns (Link[] memory);

    /// @notice Status of inter-chain adapter
    /// @param adapterId String ID of adapter
    /// @return active Enabled and can be used for bridging
    /// @return priority Priority of the adapter. 0 - max priority.
    function adapterStatus(string memory adapterId) external view returns (bool active, uint priority);

    /// @notice Inter-chain adapters available in current chain
    /// @return String IDs of adapters
    function adapters() external view returns (string[] memory);

    /// @notice Get target token for bridging
    /// @param token Address of input token for bridging
    /// @param chainTo Target chain ID
    /// @return targetToken Address of target token. address(0) when not exists.
    /// @return linkHash Hash of link string ID for bridging
    function getTarget(address token, uint16 chainTo) external view returns (address targetToken, bytes32 linkHash);

    /// @notice Transfer supported ERC20 or ERC721 token to another blockchain
    /// @param token Address of input token
    /// @param amountOrTokenId Amount for ERC-20 or tokenId for ERC-721
    /// @param chainTo Target chain ID
    /// @param nft Specify if the token is ERC-20 or ERC-721
    /// @param lock Specify if the action is to lock or burn
    function interChainTransfer(address token, uint amountOrTokenId, uint16 chainTo, bool nft, bool lock) external payable;

    /// @notice Allows the contract to receive inter-chain messages.
    /// @dev This function is designed to handle messages originating from another chain.
    /// @param srcChainId The ID of the source chain from which the message originates.
    /// @param srcAddress The address on the source chain that initiated the message.
    /// @param nonce A unique identifier for the message to prevent replay attacks.
    /// @param payload The data payload containing information or instructions from the source chain.
    /// @dev Emits an event signaling the successful reception of the inter-chain message.
    /// @dev Access to this function may be restricted to specific roles or conditions.   
    function interChainReceive(uint16 srcChainId, bytes memory srcAddress, uint64 nonce, bytes memory payload) external;

    /// @notice Add new link to the bridge
    /// Only operator can call this.
    /// @param link_ Link data
    function addLink(Link memory link_) external;

    /// @notice Update link adapters
    /// Only operator can call this.
    /// @param adapterIds String IDs of inter-chain adapters
    function setLinkAdapters(string[] memory adapterIds) external;

    function setTarget(address token, uint16 chainTo, address targetToken, bytes32 linkHash) external;

    function addAdapters(string[] memory adapterIds, uint priority) external;

    /// @notice Chaing adapter priority.
    /// Only operator can call this.
    /// @param adapterId String ID of inter-chain adapter
    /// @param newPriority New priority value for the adapter
    function changeAdapterPriority(string memory adapterId, uint newPriority) external;

    /// @notice Emergency freeze all links for the adapter
    /// Only operator can call this.
    /// @param adapterId String ID of inter-chain adapter
    /// @param reason Reason for stopping
    function emergencyStopAdapter(string memory adapterId, string memory reason) external;

    /// @notice Enable stopped adapter
    /// @param adapterId String ID of inter-chain adapter
    function enableAdapter(string memory adapterId) external;
}
