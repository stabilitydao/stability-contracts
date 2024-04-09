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
}
