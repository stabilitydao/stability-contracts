// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IStableSwapNGPool {
    function coins(uint i) external view returns (address);

    /// @notice Perform an exchange between two coins
    /// @dev Index values can be found via the `coins` public getter method
    /// @param i Index value for the coin to send
    /// @param j Index value of the coin to receive
    /// @param _dx Amount of `i` being exchanged
    /// @param _min_dy Minimum amount of `j` to receive
    /// @param _receiver Address that receives `j`
    /// @return Actual amount of `j` received
    function exchange(int128 i, int128 j, uint _dx, uint _min_dy, address _receiver) external returns (uint);

    /// @notice Deposit coins into the pool
    /// @param _amounts List of amounts of coins to deposit
    /// @param _min_mint_amount Minimum amount of LP tokens to mint from the deposit
    /// @param _receiver Address that owns the minted LP tokens
    /// @return Amount of LP tokens received by depositing
    function add_liquidity(uint[] memory _amounts, uint _min_mint_amount, address _receiver) external returns (uint);

    /// @notice Withdraw coins from the pool
    /// @dev Withdrawal amounts are based on current deposit ratios
    /// @param _burn_amount Quantity of LP tokens to burn in the withdrawal
    /// @param _min_amounts Minimum amounts of underlying coins to receive
    /// @param _receiver Address that receives the withdrawn coins
    /// @return List of amounts of coins that were withdrawn
    function remove_liquidity(
        uint _burn_amount,
        uint[] memory _min_amounts,
        address _receiver
    ) external returns (uint[] memory);
}
