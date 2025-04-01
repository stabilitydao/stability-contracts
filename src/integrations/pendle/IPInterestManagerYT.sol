// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

interface IPInterestManagerYT {
    event CollectInterestFee(uint amountInterestFee);

    function userInterest(address user) external view returns (uint128 lastPYIndex, uint128 accruedInterest);
}
