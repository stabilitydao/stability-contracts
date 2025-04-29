// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ITeller {
    function deposit(
        address depositAsset,
        uint depositAmount,
        uint minimumMint
    ) external payable returns (uint shares);
}
