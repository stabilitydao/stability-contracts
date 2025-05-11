// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title IAgentOS
/// @notice Interface for the AgentOS contract that manages AI agents as NFTs
/// @dev This interface extends IERC721Metadata to include standard NFT functionality
/// @author 0xhokugava (https://github.com/0xhokugava)
interface IAgentOS is IERC721Metadata {
    /// @notice Enum representing different types of agent jobs
    enum Job {
        PREDICTOR,
        /// @dev Agent that makes predictions
        TRADER,
        /// @dev Agent that executes trades
        ANALYZER
    }
    /// @dev Agent that analyzes data

    /// @notice Enum representing different levels of agent disclosure
    enum Disclosure {
        PUBLIC,
        /// @dev Agent's data is publicly visible
        PRIVATE
    }
    /// @dev Agent's data is only visible to owner

    /// @notice Structure containing agent parameters
    /// @param job The type of job the agent performs
    /// @param disclosure The level of data disclosure
    /// @param name The name of the agent
    /// @param isActive Whether the agent is currently active
    /// @param lastWorkedAt Timestamp of the agent's last work
    struct AgentParams {
        Job job;
        Disclosure disclosure;
        string name;
        bool isActive;
        uint lastWorkedAt;
    }

    /// @notice Structure containing asset parameters
    /// @param tokenAddress The address of the token
    /// @param symbol The token's symbol
    /// @param isActive Whether the asset is currently active
    /// @param lastUpdated Timestamp of the last update
    struct Asset {
        address tokenAddress;
        string symbol;
        bool isActive;
        uint lastUpdated;
    }

    //region ----- Errors -----
    error InsufficientPayment();
    error TokenDoesNotExist();
    error NotOwnerOrApproved();
    error AgentNotActive();
    error InvalidTokenAddress();
    error InvalidSymbol();
    error AssetAlreadyActive();
    error AssetNotActive();
    error AssetNotFound();
    error StatusAlreadySet();
    error NoBalanceToWithdraw();
    error TransferFailed();
    //endregion ----- Events -----

    //region ----- Events -----
    event AgentCreated(uint indexed tokenId, Job job, Disclosure disclosure, string name);
    event AgentWorked(uint indexed tokenId, string data);
    event MintCostUpdated(Job job, uint cost);
    event BaseURIUpdated(string baseURI);
    event AssetAdded(address indexed tokenAddress, string symbol);
    event AssetRemoved(address indexed tokenAddress);
    event AssetStatusUpdated(address indexed tokenAddress, bool isActive);
    //endregion -- Events -----

    /// @notice Mints a new agent
    /// @param job The type of job the agent will perform
    /// @param disclosure The level of data disclosure
    /// @param name The name of the agent
    /// @return tokenId The ID of the newly minted agent
    function mint(Job job, Disclosure disclosure, string memory name) external returns (uint);

    /// @notice Makes an agent perform work
    /// @param tokenId The ID of the agent
    /// @param data The data for the agent to work with
    function work(uint tokenId, string memory data) external;

    /// @notice Updates the mint cost for a specific job type
    /// @param job The type of job
    /// @param cost The new mint cost
    function updateMintCost(Job job, uint cost) external;

    /// @notice Sets the base URI for token metadata
    /// @param baseURI_ The new base URI
    function setBaseURI(string memory baseURI_) external;

    /// @notice Adds a new asset
    /// @param tokenAddress The address of the token
    /// @param symbol The token's symbol
    function addAsset(address tokenAddress, string memory symbol) external;

    /// @notice Removes an asset
    /// @param tokenAddress The address of the token to remove
    function removeAsset(address tokenAddress) external;

    /// @notice Updates the active status of an asset
    /// @param tokenAddress The address of the token
    /// @param isActive The new active status
    function updateAssetStatus(address tokenAddress, bool isActive) external;

    /// @notice Gets all active assets
    /// @return Array of active asset addresses
    function getActiveAssets() external view returns (address[] memory);

    /// @notice Gets the parameters of an agent
    /// @param tokenId The ID of the agent
    /// @return The agent's parameters
    function getAgentParams(uint tokenId) external view returns (AgentParams memory);
}
