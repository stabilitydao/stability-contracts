// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ITaskTreasuryUpgradable {
    /// @notice Get balance of a token owned by user
    /// @param _user User to get balance from
    /// @param _token Token to check balance of
    function userTokenBalance(address _user, address _token) external view returns (uint);

    /// @notice Function to deposit Funds which will be used to execute transactions on various services
    /// @param receiver Address receiving the credits
    /// @param token Token to be credited, use "0xeeee...." for ETH
    /// @param amount Amount to be credited
    function depositFunds(address receiver, address token, uint amount) external payable;

    /// @notice Function to withdraw Funds back to the _receiver
    /// @param receiver Address receiving the credits
    /// @param token Token to be credited, use "0xeeee...." for ETH
    /// @param amount Amount to be credited
    function withdrawFunds(address payable receiver, address token, uint amount) external;
}
