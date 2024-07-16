// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;
pragma abicoder v2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IUniswapV3Pool } from "../uniswapv3/IUniswapV3Pool.sol";
import { IAlgebraPool } from "../algebra/IAlgebraPool.sol";

interface IMultiPositionManager is IERC20 {
    struct VaultDetails {
        string vaultType;
        address token0;
        address token1;
        string name;
        string symbol;
        uint256 decimals;
        string token0Name;
        string token1Name;
        string token0Symbol;
        string token1Symbol;
        uint256 token0Decimals;
        uint256 token1Decimals;
        uint256 feeTier;
        uint256 totalLPTokensIssued;
        uint256 token0Balance;
        uint256 token1Balance;
        address vaultCreator;
    }

    struct AlgebraVaultDetails {
        string vaultType;
        address token0;
        address token1;
        string name;
        string symbol;
        uint256 decimals;
        string token0Name;
        string token1Name;
        string token0Symbol;
        string token1Symbol;
        uint256 token0Decimals;
        uint256 token1Decimals;
        uint256 totalLPTokensIssued;
        uint256 token0Balance;
        uint256 token1Balance;
        address vaultCreator;
    }

    struct VaultBalance {
        uint256 amountToken0;
        uint256 amountToken1;
    }

    struct LiquidityPositions {
        int24[] lowerTick;
        int24[] upperTick;
        uint16[] relativeWeight;
    }

    /**
     * @dev initializes vault
     * param _vaultManager is the address which will manage the vault being created
     * param _params is all other parameters this vault will use.
     * param _tokenName is the name of the LPT of this vault.
     * param _symbol is the symbol of the LPT of this vault.
     * param token0 is address of token0
     * param token1 is address of token1
     * param _FEE is pool fee, how much is charged for a swap
     */
    function initialize(
        address _vaultManager,
        address, //orchestrator not needed here as, if this vault is to be managed by orchestrator, _vaultManager parameter should be the orchestrator address
        address _steer,
        bytes memory _params
    ) external;

    ///
    /// @dev Deposits tokens in proportion to the vault's current holdings.
    /// @dev These tokens sit in the vault and are not used for liquidity on
    /// Uniswap until the next rebalance.
    /// @param amount0Desired Max amount of token0 to deposit
    /// @param amount1Desired Max amount of token1 to deposit
    /// @param amount0Min Revert if resulting `amount0` is less than this
    /// @param amount1Min Revert if resulting `amount1` is less than this
    /// @param to Recipient of shares
    /// @return shares Number of shares minted
    /// @return amount0 Amount of token0 deposited
    /// @return amount1 Amount of token1 deposited
    ///
    function deposit(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external returns (uint256 shares, uint256 amount0, uint256 amount1);

    /**
     * @dev burns each vault position which contains liquidity, updating fees owed to that position.
     * @dev call this before calling getTotalAmounts if total amounts must include fees. There's a function in the periphery to do so through a static call.
     */
    function poke() external;

    /**
     * @dev Withdraws tokens in proportion to the vault's holdings.
     * @param shares Shares burned by sender
     * @param amount0Min Revert if resulting `amount0` is smaller than this
     * @param amount1Min Revert if resulting `amount1` is smaller than this
     * @param to Recipient of tokens
     * @return amount0 Amount of token0 sent to recipient
     * @return amount1 Amount of token1 sent to recipient
     */
    function withdraw(
        uint256 shares,
        uint256 amount0Min,
        uint256 amount1Min,
        address to
    ) external returns (uint256 amount0, uint256 amount1);

    /**
     * @dev Internal function to pull funds from pool, update positions if necessary, then deposit funds into pool.
     * @dev reverts if it does not have any liquidity.

     * @dev newPositions requirements:
     * Each lowerTick must be lower than its corresponding upperTick
     * Each lowerTick must be greater than or equal to the tick min (-887272)
     * Each upperTick must be less than or equal to the tick max (887272)
     * All lowerTicks and upperTicks must be divisible by the pool tickSpacing--
        A 0.05% fee pool has tick spacing of 10, 0.3% has tick spacing 60. and 1% has tick spacing 200.)
     */
    function tend(
        LiquidityPositions memory newPositions,
        int256 swapAmount,
        uint160 sqrtPriceLimitX96
    ) external;

    /**
     * @dev Calculates the vault's total holdings of token0 and token1 - in
     *      other words, how much of each token the vault would hold if it withdrew
     *      all its liquidity from Uniswap.
     * @dev this function DOES NOT include fees. To include fees, first poke() and then call getTotalAmounts. There's a function inside the periphery to do so.
     */
    function getTotalAmounts()
        external
        view
        returns (uint256 total0, uint256 total1);

    //Tokens
    function vaultRegistry() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function accruedSteerFees0() external view returns (uint256);

    function accruedSteerFees1() external view returns (uint256);

    function accruedStrategistFees0() external view returns (uint256);

    function accruedStrategistFees1() external view returns (uint256);

    function maxTotalSupply() external view returns (uint256);

    function pool() external view returns (address);

    /**
     * @dev Used to collect accumulated protocol fees.
     */
    function steerCollectFees(
        uint256 amount0,
        uint256 amount1,
        address to
    ) external;

    /**
     * @dev Used to collect accumulated protocol fees.
     */
    function strategistCollectFees(
        uint256 amount0,
        uint256 amount1,
        address to
    ) external;

    /**
     * @dev Removes tokens accidentally sent to this vault.
     */
    function sweep(address token, uint256 amount, address to) external;

    /**
     * @dev Used to change deposit cap for a guarded launch or to ensure
     * vault doesn't grow too large relative to the pool. Cap is on total
     * supply rather than amounts of token0 and token1 as those amounts
     * fluctuate naturally over time.
     */
    function setMaxTotalSupply(uint256 _maxTotalSupply) external;

    /**
     * @dev Used to change the MaxTickChange and twapinterval used when checking for flash
     * loans, by default set to 500 ticks and 45 seconds, respectively
     */
    function setTWAPnums(int24 newMax, uint32 newInterval) external;

    /**
     * @dev Removes liquidity in case of emergency.
     */
    function emergencyBurn(
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) external returns (uint256 amount0, uint256 amount1);

    function getPositions() external view returns (int24[] memory lowerTick, int24[] memory upperTick, uint16[] memory relativeWeight);
}