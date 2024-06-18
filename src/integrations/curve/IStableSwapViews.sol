// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IStableSwapViews {
    /// @notice Calculate the current input dx given output dy
    /// @dev Index values can be found via the `coins` public getter method
    /// @param i Index value for the coin to send
    /// @param j Index value of the coin to receive
    /// @param dy Amount of `j` being received after exchange
    /// @return Amount of `i` predicted
    function get_dx(int128 i, int128 j, uint dy) external view returns (uint);

    /// @notice Calculate the current output dy given input dx
    /// @dev Index values can be found via the `coins` public getter method
    /// @param i Index value for the coin to send
    /// @param j Index value of the coin to receive
    /// @param dx Amount of `i` being exchanged
    /// @return Amount of `j` predicted
    function get_dy(int128 i, int128 j, uint dx) external view returns (uint);

    /// @notice Return the fee for swapping between `i` and `j`
    /// @param i Index value for the coin to send
    /// @param j Index value of the coin to receive
    /// @return Swap fee expressed as an integer with 1e10 precision
    function dynamic_fee(int128 i, int128 j, address pool) external view returns (uint);

    /// @notice Calculate addition or reduction in token supply from a deposit or withdrawal
    /// @param _amounts Amount of each coin being deposited
    /// @param _is_deposit set True for deposits, False for withdrawals
    /// @return Expected amount of LP tokens received
    function calc_token_amount(uint[] memory _amounts, bool _is_deposit) external view returns (uint);
}
