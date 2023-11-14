// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../interfaces/IPlatform.sol";


library RVaultLib {
    uint public constant MAX_COMPOUND_RATIO = 90_000;

    function baseInitCheck(
        address platform_,
        address[] memory vaultInitAddresses,
        uint[] memory vaultInitNums
    ) external view {
        uint addressesLength = vaultInitAddresses.length;
        require (addressesLength > 0, "RVaultBase: no bbToken");
        require(IPlatform(platform_).allowedBBTokenVaults(vaultInitAddresses[0]) > 0, "RVaultBase: not allowed bbToken");
        require (vaultInitNums.length == addressesLength * 2, "RVaultBase: incorrect nums");
        for (uint i; i < addressesLength; ++i) {
            require(vaultInitAddresses[i] != address(0), "RVaultBase: zero token");
            require(vaultInitNums[i] > 0, "RVaultBase: zero vesting duration");
        }
        require(vaultInitNums[addressesLength * 2 - 1] <= MAX_COMPOUND_RATIO, "RVaultBase: too high compoundRatio");
    }
}
