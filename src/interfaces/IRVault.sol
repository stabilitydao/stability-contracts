// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./IVault.sol";

interface IRVault is IVault {
    event RewardAdded(address rewardToken, uint reward);
    event RewardPaid(address indexed user, address rewardToken, uint reward);
    event SetRewardsRedirect(address owner, address receiver);
    event AddedRewardToken(address indexed token, uint indexed tokenIndex);
    event CompoundRatio(uint compoundRatio_);

    function rewardTokens() external view returns (address[] memory);

    /// @dev Immutable reward buy-back token with tokenIndex 0
    function bbToken() external view returns(address);

    /// @dev A mapping of reward tokens that able to be distributed to this contract.
    ///      Token with index 0 always is bbToken.
    function rewardToken(uint tokenIndex) external view returns(address rewardToken);

    function compoundRatio() external view returns(uint);

    function duration(uint tokenIndex) external view returns(uint durationSeconds);

    function notifyTargetRewardAmount(uint i, uint amount) external;

    /// @notice Return earned rewards for specific token and account
    ///         Accurate value returns only after updateRewards call
    ///         ((balanceOf(account)
    ///           * (rewardPerToken - userRewardPerTokenPaidForToken)) / 10**18) + rewardsForToken
    function earned(uint rewardTokenIndex, address account) external view returns (uint);

    /// @notice Update and Claim all rewards
    function getAllRewards() external;

    /// @notice Update and Claim rewards for specific token
    function getReward(uint rt) external;

    /// @notice Return reward per token ratio by reward token address
    ///                rewardPerTokenStoredForToken + (
    ///                (lastTimeRewardApplicable - lastUpdateTimeForToken)
    ///                 * rewardRateForToken * 10**18 / totalSupply)
    function rewardPerToken(uint rewardTokenIndex) external view returns (uint);

    /// @dev Receiver of rewards can be set by multisig when owner cant claim rewards himself
    function rewardsRedirect(address owner) external view returns (address receiver);

    /// @dev All rewards for given owner could be claimed for receiver address.
    function setRewardsRedirect(address owner, address receiver) external;

    /// @notice Update and Claim all rewards for given owner address. Send them to predefined receiver.
    function getAllRewardsAndRedirect(address owner) external;

    /// @notice Update and Claim all rewards for the given owner.
    ///         Sender should have allowance for push rewards for the owner.
    function getAllRewardsFor(address owner) external;

}
