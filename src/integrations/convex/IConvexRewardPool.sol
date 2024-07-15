// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IConvexRewardPool {
    struct RewardType {
        address reward_token;
        uint reward_integral;
        uint reward_remaining;
    }

    function convexBooster() external view returns (address);

    function convexPoolId() external view returns (uint);

    /// @dev get reward count
    function rewardLength() external view returns (uint);

    function rewards(uint i) external view returns (RewardType memory);

    /// @dev token -> account -> integral
    function reward_integral_for(address token, address account) external view returns (uint);

    /// @dev token -> account -> claimable
    function claimable_reward(address token, address account) external view returns (uint);

    /// @dev claim reward for given account (unguarded)
    function getReward(address account) external;

    /// @dev claim reward for given account and forward (guarded)
    function getReward(address account, address forwardTo) external;

    /// @dev withdraw balance and unwrap to the underlying lp token
    function withdraw(uint amount, bool claim) external returns (bool);

    /// @dev withdraw full balance
    function withdrawAll(bool claim) external;
}
