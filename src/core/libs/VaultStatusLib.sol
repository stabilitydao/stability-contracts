// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

library VaultStatusLib {
    uint constant internal NOT_EXIST = 0;
    uint constant internal ACTIVE = 1;
    uint constant internal DEPRECATED = 2;
    uint constant internal EMERGENCY_EXIT = 3;
    uint constant internal DISABLED = 4;
}
