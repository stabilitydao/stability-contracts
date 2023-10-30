// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ITicksFeesReader {
  function getTotalFeesOwedToPosition(
    address posManager,
    address pool,
    uint256 tokenId
  ) external view returns (uint256 token0Owed, uint256 token1Owed);
}
