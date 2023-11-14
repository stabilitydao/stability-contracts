// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./IVault.sol";

interface IRVault is IVault {
    event RewardAdded(address rewardToken, uint reward);
    event RewardPaid(address indexed user, address rewardToken, uint reward);
    event SetRewardsRedirect(address owner, address receiver);
    event AddedRewardToken(address indexed token, uint indexed tokenIndex);
    event CompoundRatio(uint compoundRatio_);

    /// @notice All vault rewarding tokens
    /// @return Reward token addresses
    function rewardTokens() external view returns (address[] memory);

    /// @notice Immutable reward buy-back token with tokenIndex 0
    function bbToken() external view returns(address);

    /// @dev A mapping of reward tokens that able to be distributed to this contract.
    /// Token with index 0 always is bbToken.
    function rewardToken(uint tokenIndex) external view returns(address rewardToken);

    /// @notice Re-investing ratio
    /// @dev Changeable ratio of revenue part for re-investing. Other part goes to rewarding by bbToken.
    /// @return Ratio of re-investing part of revenue. Denominator is 100_000.
    function compoundRatio() external view returns(uint);

    /// @notice Vesting period for distribution reward
    /// @param tokenIndex Index of rewarding token
    /// @return durationSeconds Duration for distributing of notified reward
    function duration(uint tokenIndex) external view returns(uint durationSeconds);

    /// @notice Filling vault with rewards
    /// @dev Update rewardRateForToken
    /// If period ended: reward / duration
    /// else add leftover to the reward amount and refresh the period
    /// (reward + ((periodFinishForToken - block.timestamp) * rewardRateForToken)) / duration
    /// @param tokenIndex Index of rewarding token
    /// @param amount Amount for rewarding
    function notifyTargetRewardAmount(uint tokenIndex, uint amount) external;

    /// @notice Return earned rewards for specific token and account
    ///         Accurate value returns only after updateRewards call
    ///         ((balanceOf(account)
    ///           * (rewardPerToken - userRewardPerTokenPaidForToken)) / 10**18) + rewardsForToken
    function earned(uint rewardTokenIndex, address account) external view returns (uint);

    /// @notice Update and Claim all rewards for caller
    function getAllRewards() external;

    /// @notice Update and Claim rewards for specific token
    /// @param rt Index of reward token
    function getReward(uint rt) external;

    /// @notice Return reward per token ratio by reward token address
    ///                rewardPerTokenStoredForToken + (
    ///                (lastTimeRewardApplicable - lastUpdateTimeForToken)
    ///                 * rewardRateForToken * 10**18 / totalSupply)
    /// @param rewardTokenIndex Index of reward token
    /// @return Return reward per token ratio by reward token address
    function rewardPerToken(uint rewardTokenIndex) external view returns (uint);

    /// @dev Receiver of rewards can be set by multisig when owner cant claim rewards himself
    /// @param owner Token owner address
    /// @return receiver Return reward's receiver
    function rewardsRedirect(address owner) external view returns (address receiver);

    /// @dev All rewards for given owner could be claimed for receiver address.
    /// @param owner Token owner address
    /// @param receiver New reward's receiver
    function setRewardsRedirect(address owner, address receiver) external;

    /// @notice Update and Claim all rewards for given owner address. Send them to predefined receiver.
    /// @param owner Token owner address
    function getAllRewardsAndRedirect(address owner) external;

    /// @notice Update and Claim all rewards for the given owner.
    ///         Sender should have allowance for push rewards for the owner.
    /// @param owner Token owner address
    function getAllRewardsFor(address owner) external;

}
