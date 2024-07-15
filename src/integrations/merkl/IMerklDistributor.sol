// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IMerklDistributor {
    error NotWhitelisted();

    /// @notice Toggles whitelisting for a given user and a given operator
    function toggleOperator(address user, address operator) external;

    /// @notice Claims rewards for a given set of users
    /// @dev Anyone may call this function for anyone else, funds go to destination regardless, it's just a question of
    /// who provides the proof and pays the gas: `msg.sender` is used only for addresses that require a trusted operator
    /// @param users Recipient of tokens
    /// @param tokens ERC20 claimed
    /// @param amounts Amount of tokens that will be sent to the corresponding users
    /// @param proofs Array of hashes bridging from a leaf `(hash of user | token | amount)` to the Merkle root
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint[] calldata amounts,
        bytes32[][] calldata proofs
    ) external;
}
