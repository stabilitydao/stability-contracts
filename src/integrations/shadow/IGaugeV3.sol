// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IGaugeV3 {
    /// @notice Returns an array of reward token addresses.
    /// @return An array of reward token addresses.
    function getRewardTokens() external view returns (address[] memory);

    /// @notice Returns the amount of rewards earned for an NFP.
    /// @param token The address of the token for which to retrieve the earned rewards.
    /// @param tokenId The identifier of the specific NFP for which to retrieve the earned rewards.
    /// @return reward The amount of rewards earned for the specified NFP and tokens.
    function earned(address token, uint tokenId) external view returns (uint reward);

    /// @notice retrieves rewards based on an NFP id and an array of tokens
    function getReward(uint tokenId, address[] memory tokens) external;

    /// @notice retrieves rewards based on an array of NFP ids and an array of tokens
    function getReward(uint[] calldata tokenIds, address[] memory tokens) external;

    function pool() external view returns (address);

    function nfpManager() external view returns (address);
}
