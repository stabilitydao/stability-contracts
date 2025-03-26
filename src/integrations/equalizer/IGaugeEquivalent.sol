// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IGaugeEquivalent {
    function stake() external view returns (address);

    function rewardTokens(uint i) external view returns (address);

    function rewardsListLength() external view returns (uint);

    function earnedBy(address account, address _rewardsToken) external view returns (uint);

    function left(address _rewardsToken) external view returns (uint);

    function deposit(uint amount) external;

    function withdraw(uint amount) external;

    function getReward() external;

    function getReward(address account, address[] memory tokens) external;

    function notifyRewardAmount(address _rewardsToken, uint _reward) external;

    function addReward(address _rewardsToken, address _rewardsDistributor, uint _rewardsDuration) external;
}
