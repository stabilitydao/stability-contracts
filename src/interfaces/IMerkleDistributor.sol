// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMerkleDistributor {
    event NewCampaign(string campaignId, address token, uint totalAmount, bytes32 merkleRoot, bool mint);
    event RewardClaimed(string campaignId, address user, uint amount, address receiver);
    event DelegatedClaimer(address user, address claimer);

    error InvalidProof();
    error AlreadyClaimed();
    error YouAreNotDelegated();

    /// @notice Initialize proxied contract
    function initialize(address platform_) external;

    /// @notice Setup complete campaign
    /// @param campaignId string ID of campaign ("y10", etc)
    /// @param token Reward token
    /// @param totalAmount Total amount of reward token for distribution in the campaign
    /// @param merkleRoot Root of merkle tree
    /// @param mint Mint totalAmount of token with minted rights or transfer token from multisig/governance
    function setupCampaign(
        string memory campaignId,
        address token,
        uint totalAmount,
        bytes32 merkleRoot,
        bool mint
    ) external;

    /// @notice Claim rewards
    /// @param campaignIds Array of string IDs of campaigns ("y10", "y11", etc)
    /// @param amounts Amounts of reward for each campaign
    /// @param proofs Proofs of merkle tree
    /// @param receiver Address who receive reward
    function claim(
        string[] memory campaignIds,
        uint[] memory amounts,
        bytes32[][] memory proofs,
        address receiver
    ) external;

    /// @notice Claim rewards for users who have earned them but cant execute claim call themselves, such as pool contracts
    /// Caller need to be delegated
    /// @param user Address of user who earned rewards
    /// @param campaignIds Array of string IDs of campaigns ("y10", "y11", etc)
    /// @param amounts Amounts of reward for each campaign
    /// @param proofs Proofs of merkle tree
    /// @param receiver Address who receive reward
    function claimForUser(
        address user,
        string[] memory campaignIds,
        uint[] memory amounts,
        bytes32[][] memory proofs,
        address receiver
    ) external;

    /// @notice Set delegated claimer of user's rewards by governance
    /// @param user Address of user who earns rewards
    /// @param delegatedClaimer Delegate who can claim user's rewards
    function setDelegate(address user, address delegatedClaimer) external;

    /// @notice Salvage lost tokens by governance
    /// @param token Token Address
    /// @param amount Amount of token
    /// @param receiver Receiver of token
    function salvage(address token, uint amount, address receiver) external;

    /// @notice Renounce ownable contract ownership by governance
    function renounceOwnership(address ownableContract) external;

    /// @notice View campaign data
    /// @param campaignId String IDs of campaign ("y10", etc)
    /// @return token Reward token
    /// @return totalAmount Total reward amount
    /// @return merkleRoot Root of merkle tree
    function campaign(string memory campaignId)
        external
        view
        returns (address token, uint totalAmount, bytes32 merkleRoot);

    /// @notice View is rewards was claimed for user
    /// @param user Address of user that earned reward
    /// @param campaignIds Array of string IDs of campaigns ("y10", "y11", etc)
    /// @return isClaimed Array of claimed status
    function claimed(address user, string[] memory campaignIds) external view returns (bool[] memory isClaimed);

    /// @notice Delegated caller for claim user's reward
    /// @param user User who earns rewards
    /// @return Delegate who can claim user's rewards
    function delegate(address user) external view returns (address);
}
