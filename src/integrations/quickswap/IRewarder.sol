// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IRewarder {
    /// @notice View function to see pending Token
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending SUSHI reward for a given user.
    function pendingToken(uint _pid, address _user) external view returns (uint pending);
}
