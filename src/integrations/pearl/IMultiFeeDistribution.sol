// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IMultiFeeDistribution {
    /**
     * @notice Total balance of an account, including unlocked, locked and earned tokens.
     * @param user address.
     */
    function totalBalance(address user) external view returns (uint);

    /**
     * @notice Address and claimable amount of all reward tokens for the given account.
     * @param account for rewards
     * @return rewardsData array of rewards
     * @dev this estimation doesn't include rewards that are yet to be collected from the ICHIVault via collectRewards
     */
    function claimableRewards(address account) external view returns (address[] memory, uint[] memory);

    /**
     * @notice Stake tokens to receive rewards.
     * @dev Locked tokens cannot be withdrawn for defaultLockDuration and are eligible to receive rewards.
     * @param amount to stake.
     * @param onBehalfOf address for staking.
     */
    function stake(uint amount, address onBehalfOf) external;

    function unstake(uint amount) external;

    /**
     * @notice Claim all pending staking rewards.
     * @param _rewardTokens array of reward tokens
     */
    function getReward(
        address _onBehalfOf,
        address[] memory _rewardTokens
    ) external returns (uint[] memory claimableAmounts);

    /**
     * @notice Claim all pending staking rewards.
     */
    function getAllRewards() external returns (uint[] memory claimableAmounts);
}
