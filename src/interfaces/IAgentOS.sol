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
    /// @dev Agent job placeholder
    /// @dev Agent that makes predictions
    /// @dev Agent that executes trades
    /// @dev Agent that analyzes data
    enum Job {
        NONE,
        PREDICTOR,
        TRADER,
        ANALYZER
    }

    /// @notice Enum representing different levels of agent disclosure
    /// @dev Agent's data is publicly visible
    /// @dev Agent's data is only visible to owner
    enum Disclosure {
        PUBLIC,
        PRIVATE
    }

    /// @notice Enum representing different statuses of agent
    /// @dev Agent awaiting for operator activation
    /// @dev Agent is active and ready to work
    /// @dev Agent is on tech maintainance
    enum AgentStatus {
        AWAITING,
        ACTIVE,
        MAINTENANCE
    }

    /// @notice Structure containing agent parameters
    /// @param job The type of job the agent performs
    /// @param disclosure The level of data disclosure
    /// @param name The name of the agent
    /// @param isActive Whether the agent is currently active
    /// @param lastWorkedAt Timestamp of the agent's last work
    struct AgentParams {
        Job job;
        Disclosure disclosure;
        AgentStatus agentStatus;
        string name;
        uint lastWorkedAt;
    }

    //region ----- Errors -----
    error InsufficientPayment();
    error TokenDoesNotExist();
    error NotOwnerOrApproved();
    error AgentNotActive();
    error AssetAlreadyActive();
    error AssetNotActive();
    error StatusAlreadySet();
    //endregion ----- Events -----

    //region ----- Events -----
    event AgentCreated(uint indexed tokenId, Job job, Disclosure disclosure, AgentStatus agentStatus, string name);
    event AgentWorked(uint indexed tokenId, Job job, string data);
    event MintCostUpdated(Job job, uint cost);
    event BaseURIUpdated(string baseURI);
    event AssetAdded(address indexed tokenAddress);
    event AssetRemoved(address indexed tokenAddress);
    event AgentStatusUpdated(uint indexed tokenId, AgentStatus agentStatus);
    event AgentJobFeeSetted(Job job, uint jobFee);
    //endregion -- Events -----

    /// @notice Mints a new agent
    /// @param job The type of job the agent will perform
    /// @param disclosure The level of data disclosure
    /// @param name The name of the agent
    /// @return tokenId The ID of the newly minted agent
    function mint(
        Job job,
        Disclosure disclosure,
        AgentStatus agentStatus,
        string memory name
    ) external returns (uint);

    /// @notice Makes an agent perform work
    /// @param tokenId The ID of the agent
    /// @param data The data for the agent to work with
    function work(uint tokenId, Job job, string memory data) external;

    /// @notice Set the mint cost for a specific job type
    /// @param job The type of job
    /// @param cost The new mint cost
    function setMintCost(Job job, uint cost) external;

    /// @notice Sets the base URI for token metadata
    /// @param baseURI_ The new base URI
    function setBaseURI(string memory baseURI_) external;

    /// @notice Adds a new asset
    /// @param tokenAddress The address of the token
    function addAsset(address tokenAddress) external;

    /// @notice Removes an asset
    /// @param tokenAddress The address of the token to remove
    function removeAsset(address tokenAddress) external;

    /// @notice Gets all active assets
    /// @return Asset addresses array
    function getAllAssets() external view returns (address[] memory);

    /// @notice Gets the parameters of an agent
    /// @param tokenId The ID of the agent
    /// @return The agent's parameters
    function getAgentParams(uint tokenId) external view returns (AgentParams memory);

    /// @notice Sets status of an agent
    /// @param tokenId The ID of the agent
    /// @param agentStatus of the agent to be setted
    function setAgentStatus(uint tokenId, AgentStatus agentStatus) external;

    /// @notice Set an agent job fee
    /// @param job The type of job
    /// @param jobFee price
    function setJobFee(Job job, uint jobFee) external;
}
