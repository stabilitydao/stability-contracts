// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IXShadow {
    /**
     * @dev exit instantly with a penalty
     * @param amount amount of xShadows to exit
     */
    function exit(uint amount) external returns(uint exitedAmount);

    /// @notice address of the shadow token
    function SHADOW() external view returns (address);

}
