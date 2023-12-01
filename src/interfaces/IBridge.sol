// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title Stability Bridge
/// @author Alien Deployer (https://github.com/a17)
interface IBridge {
    struct Link {
        /// @dev Sorted chain A (chain A < chain B)
        uint64 chainA;
        /// @dev Sorted chain B
        uint64 chainB;
        /// @dev Address of Bridge contract in chain A
        address bridgeA;
        /// @dev Address of Bridge contract in chain B
        address bridgeB;
        /// @dev String IDs of inter-chain adapters supported for this route. Not used in link hash calculation.
        string[] interChainAdapterId;
    }

    /// @notice Current chain ID
    function chainId() external view returns (uint64);

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
    function getTarget(address token, uint64 chainTo) external view returns (address targetToken, bytes32 linkHash);

    /// @notice Transfer supported ERC20 or ERC721 token to another blockchain
    /// @param token Address of input token
    /// @param amountOrTokenId Amount for ERC-20 or tokenId for ERC-721
    /// @param chainTo Target chain ID
    function interChainTransfer(address token, uint amountOrTokenId, uint64 chainTo) external payable;

    /// @notice Receive tokens from another blockchain.
    /// Only adapters can call this.
    /// @param token Address of output token for bridging
    /// @param amountOrTokenId Amount for ERC-20 or tokenId for ERC-721
    /// @param chainFrom Source chain ID
    function interChainReceive(address token, uint amountOrTokenId, uint64 chainFrom) external;

    /// @notice Add new link to the bridge
    /// Only operator can call this.
    /// @param link_ Link data
    function addLink(Link memory link_) external;

    /// @notice Update link adapters
    /// Only operator can call this.
    /// @param adapterIds String IDs of inter-chain adapters
    function setLinkAdapters(string[] memory adapterIds) external;

    function setTarget(address token, uint64 chainTo, address targetToken, bytes32 linkHash) external;

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
