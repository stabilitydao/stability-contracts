// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IComet {
    function baseToken() external view returns (address);

    function supply(address asset, uint amount) external;

    function withdraw(address asset, uint amount) external;

    function withdrawTo(address to, address asset, uint amount) external;

    function balanceOf(address owner) external view returns (uint);

    function accrueAccount(address account) external;
}
