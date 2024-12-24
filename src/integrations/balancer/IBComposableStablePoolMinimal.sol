// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

interface IBComposableStablePoolMinimal {
    /**
     * @dev Returns all normalized weights, in the same order as the Pool's tokens.
     */
    function getPoolId() external view returns (bytes32);
    function getSwapFeePercentage() external view returns (uint);
    function getAmplificationParameter() external view returns (uint value, bool isUpdating, uint precision);
    function getScalingFactors() external view returns (uint[] memory);
    function getBptIndex() external view returns (uint);
    function getVault() external view returns (address);

    function updateTokenRateCache(address token) external;
}
