// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../interfaces/IPlatform.sol";
import "../../interfaces/IRVault.sol";

library RVaultLib {
    uint public constant MAX_COMPOUND_RATIO = 90_000;
    
    // Custom Errors

    function baseInitCheck(
        address platform_,
        address[] memory vaultInitAddresses,
        uint[] memory vaultInitNums
    ) external view {
        uint addressesLength = vaultInitAddresses.length;
        if(addressesLength == 0){
            revert IRVault.NoBBToken();
        }
        if(IPlatform(platform_).allowedBBTokenVaults(vaultInitAddresses[0]) == 0){
            revert IRVault.NotAllowedBBToken();
        }
        if(vaultInitNums.length != addressesLength * 2){
            revert IRVault.IncorrectNums();
        }
        // nosemgrep
        for (uint i; i < addressesLength; ++i) {
            if(vaultInitAddresses[i] == address(0)){
                revert IRVault.ZeroToken();
            }
            if(vaultInitNums[i] == 0){
                revert IRVault.ZeroVestingDuration();
            }
        }
        if(vaultInitNums[addressesLength * 2 - 1] > MAX_COMPOUND_RATIO){
            revert IRVault.TooHighCompoundRation();
        }
    }
}
