// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

interface IBWeightedPoolMinimal {
    /**
     * @dev Returns all normalized weights, in the same order as the Pool's tokens.
     */
    function getNormalizedWeights() external view returns (uint[] memory);
    function getPoolId() external view returns (bytes32);
    function getSwapFeePercentage() external view returns (uint);
    function getVault() external view returns (address);
}
