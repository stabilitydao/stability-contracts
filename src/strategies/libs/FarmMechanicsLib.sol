// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

library FarmMechanicsLib {
    // Staking to gauge/farm to earn rewards
    string internal constant CLASSIC = "Classic";
    // Merkl protocol rewards calculated off-chain and credited periodically
    string internal constant MERKL = "Merkl";
    // Automatic farming without staking with on-chain calculated rewards
    string internal constant AUTO = "Auto";
}
