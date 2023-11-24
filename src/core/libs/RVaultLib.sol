// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../interfaces/IPlatform.sol";


library RVaultLib {
    uint public constant MAX_COMPOUND_RATIO = 90_000;
    
    // Custom Errors
    error NoBBToken();
    error NotAllowedBBToken();
    error IncorrectNums();
    error ZeroToken();
    error ZeroVestingDuration();
    error TooHighCompoundRation();

    function baseInitCheck(
        address platform_,
        address[] memory vaultInitAddresses,
        uint[] memory vaultInitNums
    ) external view {
        uint addressesLength = vaultInitAddresses.length;
        if(addressesLength == 0) revert NoBBToken();
        if(IPlatform(platform_).allowedBBTokenVaults(vaultInitAddresses[0]) == 0) revert NotAllowedBBToken();
        if(vaultInitNums.length != addressesLength * 2) revert IncorrectNums();
        // nosemgrep
        for (uint i; i < addressesLength; ++i) {
            if(vaultInitAddresses[i] == address(0)) revert ZeroToken();
            if(vaultInitNums[i] == 0) revert ZeroVestingDuration();
        }
        if(vaultInitNums[addressesLength * 2 - 1] > MAX_COMPOUND_RATIO) revert TooHighCompoundRation();
    }
}
