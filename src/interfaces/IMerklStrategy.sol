// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IMerklStrategy {
    /// @notice Toggle user operator status on Merkl Distributor
    /// @dev Only whitelisted operators can claim Merkl rewards for user (strategy address).
    /// Only Stability Platform operators can call this
    /// @param distributor Address of Merkl Distributor contract
    /// @param operator Address of Merkl rewards claimer that can be HardWorker.dedicatedServerMsgSender
    function toggleDistributorUserOperator(address distributor, address operator) external;

    /// @notice Claim rewards to multisig for future distribution
    /// Only Stability Platform operators can call this
    function claimToMultisig(
        address distributor,
        address[] calldata tokens,
        uint[] calldata amounts,
        bytes32[][] calldata proofs
    ) external;
}
