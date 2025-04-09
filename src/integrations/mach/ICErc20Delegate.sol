// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ICErc20Delegate {
    function accrualBlockTimestamp() external view returns (uint);
    function admin() external view returns (address);

    function allowance(address, address) external view returns (uint);
    function balanceOf(address) external view returns (uint);

    function borrowBalanceStored(address) external view returns (uint);
    function borrowIndex() external view returns (uint);
    function borrowRatePerTimestamp() external view returns (uint);
    function comptroller() external view returns (address);

    function decimals() external view returns (uint8);

    function exchangeRateStored() external view returns (uint);
    function getAccountSnapshot(address) external view returns (uint, uint, uint, uint);
    function getCash() external view returns (uint);
    function implementation() external view returns (address);

    function interestRateModel() external view returns (address);
    function isCToken() external view returns (bool);

    function name() external view returns (string memory);

    function pendingAdmin() external view returns (address);
    function protocolSeizeShareMantissa() external view returns (uint);
    function reserveFactorMantissa() external view returns (uint);
    function supplyRatePerTimestamp() external view returns (uint);

    function symbol() external view returns (string memory);

    function totalBorrows() external view returns (uint);
    function totalReserves() external view returns (uint);
    function totalSupply() external view returns (uint);
    function underlying() external view returns (address);

    function mint(uint) external returns (uint success);
    function mintAsCollateral(uint) external returns (uint success);
    function redeem(uint) external returns (uint success);
    function redeemUnderlying(uint) external returns (uint success);

    function borrow(uint borrowAmount) external returns (uint);
    function repayBorrow(uint repayAmount) external returns (uint);
    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint);

    function transfer(address dst, uint amount) external returns (bool);
    function transferFrom(address src, address dst, uint amount) external returns (bool);
    function approve(address spender, uint amount) external returns (bool);
}