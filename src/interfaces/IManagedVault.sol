// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @dev Managed vaults allow the owner of the VaultManager token to change their parameters.
/// @author JodsMigel (https://github.com/JodsMigel)
interface IManagedVault {
    //region ----- Custom Errors -----
    error CantRemoveRewardToken();
    error NotVaultManager();
    error IncorrectRewardToken(address token);
    error CantChangeDuration(uint incorrectDuration);
    //endregion -- Custom Errors -----

    /// @notice VaultManager contract can change managed vault parameters by this method
    /// @param vaultInitAddresses All vault init addresses. Not changeable init addresses must be provided correctly.
    /// @param vaultInitNums All vault init numbers. Not changeable init numbers must be provided correctly.
    function changeParams(address[] memory vaultInitAddresses, uint[] memory vaultInitNums) external;
}
