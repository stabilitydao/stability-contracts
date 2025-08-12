// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IRecoveryToken {
    error TransfersPausedForAccount(address account);

    event AccountPaused(address indexed account, bool paused);

    /// @dev Init
    function initialize(address platform_, address target_) external;

    /// @notice Address of target of recovery
    function target() external view returns (address);

    /// @notice Mint tokens by target
    function mint(address account, uint amount) external;

    /// @notice Pause transfers from address
    function setAddressPaused(address account, bool paused) external;
}
