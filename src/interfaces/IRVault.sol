// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

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

}
