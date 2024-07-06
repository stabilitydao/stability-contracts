// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ITicksFeesReader {
    function getTotalFeesOwedToPosition(
        address posManager,
        address pool,
        uint tokenId
    ) external view returns (uint token0Owed, uint token1Owed);
}
