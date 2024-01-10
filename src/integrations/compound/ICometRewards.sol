// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ICometRewards {
    function claim(address comet, address src, bool shouldAccrue) external;

    function claimTo(address comet, address src, address to, bool shouldAccrue) external;
}
