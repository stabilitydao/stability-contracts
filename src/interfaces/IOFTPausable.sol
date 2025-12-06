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
}
