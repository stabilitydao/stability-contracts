// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IVotingEscrow {
    struct LockedBalance {
        int128 amount;
        uint end;
    }

    function locked(uint tokenId) external view returns (LockedBalance memory);

    /// @notice Get the current voting power for `_tokenId`
    function balanceOfNFT(uint _tokenId) external view returns (uint);

    /// @notice Deposit `_value` tokens for `msg.sender` and lock for `_lock_duration`
    /// @param _value Amount to deposit
    /// @param _lock_duration Number of seconds to lock tokens for (rounded down to nearest week)
    function create_lock(uint _value, uint _lock_duration) external returns (uint);

    function merge(uint _from, uint _to) external;
}
