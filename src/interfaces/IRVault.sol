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

    function getAllRewards() external;

}
