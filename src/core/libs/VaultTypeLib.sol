// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

library VaultTypeLib {
    string constant internal COMPOUNDING = 'Compounding';
    string constant internal REWARDING = 'Rewarding';
    string constant internal REWARDING_MANAGED = 'Rewarding Managed';
    string constant internal SPLITTER_MANAGED = 'Splitter Managed';
    string constant internal SPLITTER_AUTO = 'Splitter Automatic';
}
