// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./IVault.sol";

/// @notice Interface of Rewarding Vault
/// @author Alien Deployer (https://github.com/a17)
/// @author JodsMigel (https://github.com/JodsMigel)
/// @author 0xhokugava (https://github.com/0xhokugava)
interface IRVault is IVault {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error NotAllowed();
    error Overflow(uint maxAmount);
    error RTNotFound();
    error NoBBToken();
    error NotAllowedBBToken();
    error IncorrectNums();
    error ZeroToken();
    error ZeroVestingDuration();
    error TooHighCompoundRation();
    error RewardIsTooSmall();
    // error RewardIsTooBig();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event RewardAdded(address rewardToken, uint reward);
    event RewardPaid(address indexed user, address rewardToken, uint reward);
    event SetRewardsRedirect(address owner, address receiver);
    event AddedRewardToken(address indexed token, uint indexed tokenIndex);
    event CompoundRatio(uint compoundRatio_);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.RVaultBase
    struct RVaultBaseStorage {
        /// @inheritdoc IRVault
        mapping(uint tokenIndex => address rewardToken) rewardToken;
        /// @inheritdoc IRVault
        mapping(uint tokenIndex => uint durationSeconds) duration;
        /// @inheritdoc IRVault
        mapping(address owner => address receiver) rewardsRedirect;
        /// @dev Timestamp value when current period of rewards will be ended
        mapping(uint tokenIndex => uint finishTimestamp) periodFinishForToken;
        /// @dev Reward rate in normal circumstances is distributed rewards divided on duration
        mapping(uint tokenIndex => uint rewardRate) rewardRateForToken;
        /// @dev Last rewards snapshot time. Updated on each share movements
        mapping(uint tokenIndex => uint lastUpdateTimestamp) lastUpdateTimeForToken;
        /// @dev Rewards snapshot calculated from rewardPerToken(rt). Updated on each share movements
        mapping(uint tokenIndex => uint rewardPerTokenStored) rewardPerTokenStoredForToken;
        /// @dev User personal reward rate snapshot. Updated on each share movements
        mapping(uint tokenIndex => mapping(address user => uint rewardPerTokenPaid)) userRewardPerTokenPaidForToken;
        /// @dev User personal earned reward snapshot. Updated on each share movements
        mapping(uint tokenIndex => mapping(address user => uint earned)) rewardsForToken;
        /// @inheritdoc IRVault
        uint rewardTokensTotal;
        /// @inheritdoc IRVault
        uint compoundRatio;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice All vault rewarding tokens
    /// @return Reward token addresses
    function rewardTokens() external view returns (address[] memory);

    /// @return Total of bbToken + boost reward tokens
    function rewardTokensTotal() external view returns (uint);

    /// @notice Immutable reward buy-back token with tokenIndex 0
    function bbToken() external view returns (address);

    /// @dev A mapping of reward tokens that able to be distributed to this contract.
    /// Token with index 0 always is bbToken.
    function rewardToken(uint tokenIndex) external view returns (address rewardToken_);

    /// @notice Re-investing ratio
    /// @dev Changeable ratio of revenue part for re-investing. Other part goes to rewarding by bbToken.
    /// @return Ratio of re-investing part of revenue. Denominator is 100_000.
    function compoundRatio() external view returns (uint);

    /// @notice Vesting period for distribution reward
    /// @param tokenIndex Index of rewarding token
    /// @return durationSeconds Duration for distributing of notified reward
    function duration(uint tokenIndex) external view returns (uint durationSeconds);

    /// @notice Return earned rewards for specific token and account
    ///         Accurate value returns only after updateRewards call
    ///         ((balanceOf(account)
    ///           * (rewardPerToken - userRewardPerTokenPaidForToken)) / 10**18) + rewardsForToken
    function earned(uint rewardTokenIndex, address account) external view returns (uint);

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

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Filling vault with rewards
    /// @dev Update rewardRateForToken
    /// If period ended: reward / duration
    /// else add leftover to the reward amount and refresh the period
    /// (reward + ((periodFinishForToken - block.timestamp) * rewardRateForToken)) / duration
    /// @param tokenIndex Index of rewarding token
    /// @param amount Amount for rewarding
    function notifyTargetRewardAmount(uint tokenIndex, uint amount) external;

    /// @notice Update and Claim all rewards for caller
    function getAllRewards() external;

    /// @notice Update and Claim rewards for specific token
    /// @param rt Index of reward token
    function getReward(uint rt) external;

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
