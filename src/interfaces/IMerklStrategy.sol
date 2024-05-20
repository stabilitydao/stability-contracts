// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IMerklStrategy {
    /// @notice Toggle user operator status on Merkl Distributor
    /// @dev Only whitelisted operators can claim Merkl rewards for user (strategy address).
    /// Only Stability Platform operators can call this
    /// @param distributor Address of Merkl Distributor contract
    /// @param operator Address of Merkl rewards claimer that can be HardWorker.dedicatedServerMsgSender
    function toggleDistributorUserOperator(address distributor, address operator) external;
}
