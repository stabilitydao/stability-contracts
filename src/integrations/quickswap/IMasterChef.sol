// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

interface IMasterChef {
    /// @notice Info of each MCV2 user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of SUSHI entitled to the user.
    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    struct PoolInfo {
        uint256 accSushiPerShare; // Accumulated SUSHI per share, times 1e12. See below.
        uint256 lastRewardBlock;  // Last block number that SUSHI distribution occurs.
        uint256 allocPoint;       // How many allocation points assigned to this pool. SUSHI to distribute per block.
    }

    function userInfo(uint pid, address user) external returns (UserInfo memory);

    function poolInfo(uint256 pid) external view returns (PoolInfo memory);

    /// @notice View function to see pending SUSHI on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending SUSHI reward for a given user.
    function pendingSushi(uint256 _pid, address _user) external view returns (uint256 pending);

    /// @notice Deposit LP tokens to MCV2 for SUSHI allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to deposit.
    /// @param to The receiver of `amount` deposit benefit.
    function deposit(uint256 pid, uint256 amount, address to) external;

    /// @notice Withdraw LP tokens from MCV2.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens.
    function withdraw(uint256 pid, uint256 amount, address to) external;

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of SUSHI rewards.
    function harvest(uint256 pid, address to) external;

    function getRewarder(uint256 _pid, uint256 _rid) external view returns (address);

    function updatePool(uint256 pid) external returns (PoolInfo memory pool);
}