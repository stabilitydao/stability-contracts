// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IOFT} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

interface IOFTPausable is IOFT {
    error Paused();
    event Pause(address indexed account, bool paused);

    /// @notice True if the given account is paused and is not able to transfer bridget tokens
    function paused(address account_) external view returns (bool);

    /// @notice Set paused state for account
    /// @param account Address of account
    /// @param paused_ True - set paused, false - unpaused
    function setPaused(address account, bool paused_) external;

    /// @dev See OptionsBuilder.addExecutorLzReceiveOption
    /// @param gas_ The gasLimit used on the lzReceive() function in the OApp.
    /// @param value_ The msg.value passed to the lzReceive() function in the OApp (use 0).
    function buildOptions(uint128 gas_, uint128 value_) external pure returns (bytes memory);
}
