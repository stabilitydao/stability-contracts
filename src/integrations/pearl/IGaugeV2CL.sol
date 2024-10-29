// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IGaugeV2CL {
    function box() external view returns (address);

    function rewardToken() external view returns (address);

    function balanceOf(address account) external view returns (uint);

    ///@notice see earned rewards for user
    function earnedReward(address account) external view returns (uint);

    ///@notice deposit amount TOKEN
    function deposit(uint amount) external;

    ///@notice withdraw a certain amount of TOKEN
    function withdraw(uint amount) external;

    ///@notice User harvest function
    function collectReward() external;

    function periodFinish() external view returns(uint);

    /**
     * @notice Notifies the contract of a reward amount.
     * @param token The address of the reward token.
     * @param reward The reward amount.
     */
    function notifyRewardAmount(address token, uint reward) external;
}
