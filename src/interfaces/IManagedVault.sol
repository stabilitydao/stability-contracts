// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

/// @dev Managed vaults allow the owner of the VaultManager token to change their parameters.
interface IManagedVault {
    /// @notice VaultManager contract can change managed vault parameters by this method
    /// @param vaultInitAddresses All vault init addresses. Not changeable init addresses must be provided correctly.
    /// @param vaultInitNums All vault init numbers. Not changeable init numbers must be provided correctly.
    function changeParams(address[] memory vaultInitAddresses, uint[] memory vaultInitNums) external;
}
