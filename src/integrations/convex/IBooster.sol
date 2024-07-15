// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IBooster {
    /// @notice deposit lp tokens and stake
    function deposit(uint pid, uint amount) external returns (bool);

    /// @notice deposit all lp tokens and stake
    function depositAll(uint pid) external returns (bool);
}
