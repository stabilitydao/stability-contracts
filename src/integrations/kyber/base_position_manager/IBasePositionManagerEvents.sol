// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IBasePositionManagerEvents {
    /// @notice Emitted when a token is minted for a given position
    /// @param tokenId the newly minted tokenId
    /// @param poolId poolId of the token
    /// @param liquidity liquidity minted to the position range
    /// @param amount0 token0 quantity needed to mint the liquidity
    /// @param amount1 token1 quantity needed to mint the liquidity
    event MintPosition(uint indexed tokenId, uint80 indexed poolId, uint128 liquidity, uint amount0, uint amount1);

    /// @notice Emitted when a token is burned
    /// @param tokenId id of the token
    event BurnPosition(uint indexed tokenId);

    /// @notice Emitted when add liquidity
    /// @param tokenId id of the token
    /// @param liquidity the increase amount of liquidity
    /// @param amount0 token0 quantity needed to increase liquidity
    /// @param amount1 token1 quantity needed to increase liquidity
    /// @param additionalRTokenOwed additional rToken earned
    event AddLiquidity(uint indexed tokenId, uint128 liquidity, uint amount0, uint amount1, uint additionalRTokenOwed);

    /// @notice Emitted when remove liquidity
    /// @param tokenId id of the token
    /// @param liquidity the decease amount of liquidity
    /// @param amount0 token0 quantity returned when remove liquidity
    /// @param amount1 token1 quantity returned when remove liquidity
    /// @param additionalRTokenOwed additional rToken earned
    event RemoveLiquidity(
        uint indexed tokenId, uint128 liquidity, uint amount0, uint amount1, uint additionalRTokenOwed
    );

    /// @notice Emitted when burn position's RToken
    /// @param tokenId id of the token
    /// @param rTokenBurn amount of position's RToken burnt
    event BurnRToken(uint indexed tokenId, uint rTokenBurn);

    /// @notice Emitted when sync fee growth
    /// @param tokenId id of the token
    /// @param additionalRTokenOwed additional rToken earned
    event SyncFeeGrowth(uint indexed tokenId, uint additionalRTokenOwed);
}
