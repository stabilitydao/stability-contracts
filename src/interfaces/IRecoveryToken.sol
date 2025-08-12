// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IRecoveryToken {
    /// @dev Init
    function initialize(address platform_, address target_) external;

    /// @notice Address of target of recovery
    function target() external view returns (address);
}
