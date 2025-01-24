// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IMerkleDistributor {
    event NewCampaign(string campaignId, address token, uint totalAmount, bytes32 merkleRoot, bool mint);
    event RewardClaimed(string campaignId, address user, uint amount, address receiver);

    error InvalidProof();
    error AlreadyClaimed();

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

    /// @notice Claim rewards for users who have earned them but cant execute claim call themselves, such as pool contracts
    /// @param user Address of contact who cant claim
    /// @param campaignIds Array of string IDs of campaigns ("y10", "y11", etc)
    /// @param amounts Amounts of reward for each campaign
    /// @param proofs Proofs of merkle tree
    /// @param receiver Address who receive reward
    function claimForUserWhoCantClaim(
        address user,
        string[] memory campaignIds,
        uint[] memory amounts,
        bytes32[][] memory proofs,
        address receiver
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
}
