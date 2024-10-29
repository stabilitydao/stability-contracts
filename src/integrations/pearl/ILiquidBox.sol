// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ILiquidBox {
    /**
     * @notice Deposits tokens into the vault, distributing them
     * in proportion to the current holdings.
     * @dev Tokens deposited remain in the vault until the next
     * rebalance and are not utilized for liquidity on Pearl.
     * @param amount0Desired Maximum amount of token0 to deposit
     * @param amount1Desired Maximum amount of token1 to deposit
     * @param to Recipient of shares
     * @param amount0Min Reverts if the resulting amount0 is less than this
     * @param amount1Min Reverts if the resulting amount1 is less than this
     * @return shares Number of shares minted
     * @return amount0 Amount of token0 deposited
     * @return amount1 Amount of token1 deposited
     */
    function deposit(
        uint amount0Desired,
        uint amount1Desired,
        address to,
        uint amount0Min,
        uint amount1Min
    ) external returns (uint shares, uint amount0, uint amount1);

    /**
     * @notice Withdraws tokens in proportion to the vault's holdings.
     * @param shares Shares burned by sender
     * @param amount0Min Revert if resulting `amount0` is smaller than this
     * @param amount1Min Revert if resulting `amount1` is smaller than this
     * @param to Recipient of tokens
     * @return amount0 Amount of token0 sent to recipient
     * @return amount1 Amount of token1 sent to recipient
     */
    function withdraw(
        uint shares,
        address to,
        uint amount0Min,
        uint amount1Min
    ) external returns (uint amount0, uint amount1);

    /**
     * @notice Calculates the vault's total holdings of token0 and token1 - in
     * other words, how much of each token the vault would hold if it withdrew
     * all its liquidity from Uniswap.
     */
    function getTotalAmounts() external view returns (
        uint total0,
        uint total1,
        uint pool0,
        uint pool1,
        uint128 liquidity
    );

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function gauge() external view returns (address);

    function getRequiredAmountsForInput(
        uint amount0,
        uint amount1
    ) external view returns (uint, uint);
}
