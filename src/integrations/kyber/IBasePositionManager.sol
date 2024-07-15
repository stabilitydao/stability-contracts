// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IRouterTokenHelper} from "./IRouterTokenHelper.sol";
import {IBasePositionManagerEvents} from "./base_position_manager/IBasePositionManagerEvents.sol";

interface IBasePositionManager is IRouterTokenHelper, IBasePositionManagerEvents {
    struct Position {
        // the nonce for permits
        uint96 nonce;
        // the address that is approved for spending this token
        address operator;
        // the ID of the pool with which this token is connected
        uint80 poolId;
        // the tick range of the position
        int24 tickLower;
        int24 tickUpper;
        // the liquidity of the position
        uint128 liquidity;
        // the current rToken that the position owed
        uint rTokenOwed;
        // fee growth per unit of liquidity as of the last update to liquidity
        uint feeGrowthInsideLast;
    }

    struct PoolInfo {
        address token0;
        uint24 fee;
        address token1;
    }

    /// @notice Params for the first time adding liquidity, mint new nft to sender
    /// @param token0 the token0 of the pool
    /// @param token1 the token1 of the pool
    ///   - must make sure that token0 < token1
    /// @param fee the pool's fee in fee units
    /// @param tickLower the position's lower tick
    /// @param tickUpper the position's upper tick
    ///   - must make sure tickLower < tickUpper, and both are in tick distance
    /// @param ticksPrevious the nearest tick that has been initialized and lower than or equal to
    ///   the tickLower and tickUpper, use to help insert the tickLower and tickUpper if haven't initialized
    /// @param amount0Desired the desired amount for token0
    /// @param amount1Desired the desired amount for token1
    /// @param amount0Min min amount of token 0 to add
    /// @param amount1Min min amount of token 1 to add
    /// @param recipient the owner of the position
    /// @param deadline time that the transaction will be expired
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        int24[2] ticksPrevious;
        uint amount0Desired;
        uint amount1Desired;
        uint amount0Min;
        uint amount1Min;
        address recipient;
        uint deadline;
    }

    /// @notice Params for adding liquidity to the existing position
    /// @param tokenId id of the position to increase its liquidity
    /// @param ticksPrevious the nearest tick that has been initialized and lower than or equal to
    ///   the tickLower and tickUpper, use to help insert the tickLower and tickUpper if haven't initialized
    ///   only needed if the position has been closed and the owner wants to add more liquidity
    /// @param amount0Desired the desired amount for token0
    /// @param amount1Desired the desired amount for token1
    /// @param amount0Min min amount of token 0 to add
    /// @param amount1Min min amount of token 1 to add
    /// @param deadline time that the transaction will be expired
    struct IncreaseLiquidityParams {
        uint tokenId;
        int24[2] ticksPrevious;
        uint amount0Desired;
        uint amount1Desired;
        uint amount0Min;
        uint amount1Min;
        uint deadline;
    }

    /// @notice Params for remove liquidity from the existing position
    /// @param tokenId id of the position to remove its liquidity
    /// @param amount0Min min amount of token 0 to receive
    /// @param amount1Min min amount of token 1 to receive
    /// @param deadline time that the transaction will be expired
    struct RemoveLiquidityParams {
        uint tokenId;
        uint128 liquidity;
        uint amount0Min;
        uint amount1Min;
        uint deadline;
    }

    /// @notice Burn the rTokens to get back token0 + token1 as fees
    /// @param tokenId id of the position to burn r token
    /// @param amount0Min min amount of token 0 to receive
    /// @param amount1Min min amount of token 1 to receive
    /// @param deadline time that the transaction will be expired
    struct BurnRTokenParams {
        uint tokenId;
        uint amount0Min;
        uint amount1Min;
        uint deadline;
    }

    /// @notice Creates a new pool if it does not exist, then unlocks if it has not been unlocked
    /// @param token0 the token0 of the pool
    /// @param token1 the token1 of the pool
    /// @param fee the fee for the pool
    /// @param currentSqrtP the initial price of the pool
    /// @return pool returns the pool address
    function createAndUnlockPoolIfNecessary(
        address token0,
        address token1,
        uint24 fee,
        uint160 currentSqrtP
    ) external payable returns (address pool);

    function mint(MintParams calldata params)
        external
        payable
        returns (uint tokenId, uint128 liquidity, uint amount0, uint amount1);

    function addLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        returns (uint128 liquidity, uint amount0, uint amount1, uint additionalRTokenOwed);

    function removeLiquidity(RemoveLiquidityParams calldata params)
        external
        returns (uint amount0, uint amount1, uint additionalRTokenOwed);

    function burnRTokens(BurnRTokenParams calldata params)
        external
        returns (uint rTokenQty, uint amount0, uint amount1);

    /**
     * @dev Burn the token by its owner
     * @notice All liquidity should be removed before burning
     */
    function burn(uint tokenId) external payable;

    function syncFeeGrowth(uint tokenId) external returns (uint additionalRTokenOwed);

    function positions(uint tokenId) external view returns (Position memory pos, PoolInfo memory info);

    function addressToPoolId(address pool) external view returns (uint80);

    function isRToken(address token) external view returns (bool);

    function nextPoolId() external view returns (uint80);

    function nextTokenId() external view returns (uint);

    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
