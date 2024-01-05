// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

library VaultStatusLib {
    uint internal constant NOT_EXIST = 0;
    uint internal constant ACTIVE = 1;
    uint internal constant DEPRECATED = 2;
    uint internal constant EMERGENCY_EXIT = 3;
    uint internal constant DISABLED = 4;
    uint internal constant DEPOSITS_UNAVAILABLE = 5;
}
