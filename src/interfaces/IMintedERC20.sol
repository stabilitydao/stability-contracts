// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IMintedERC20 {
    function mint(address to, uint amount) external;
}
