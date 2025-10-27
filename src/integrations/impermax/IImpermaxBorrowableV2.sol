// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IImpermaxBorrowableV2 {

    /*** Impermax ERC20 ***/

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);
    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    /*** Pool Token ***/

    event Mint(address indexed sender, address indexed minter, uint mintAmount, uint mintTokens);
    event Redeem(address indexed sender, address indexed redeemer, uint redeemAmount, uint redeemTokens);
    event Sync(uint totalBalance);

    function underlying() external view returns (address);
    function factory() external view returns (address);
    function totalBalance() external view returns (uint);
    function MINIMUM_LIQUIDITY() external pure returns (uint);

    function exchangeRate() external returns (uint);
    function mint(address minter) external returns (uint mintTokens);
    function redeem(address redeemer) external returns (uint redeemAmount);
    function skim(address to) external;
    function sync() external;

    function _setFactory() external;

    /*** Borrowable ***/

    event BorrowApproval(address indexed owner, address indexed spender, uint value);
    event Borrow(address indexed sender, address indexed borrower, address indexed receiver, uint borrowAmount, uint repayAmount, uint accountBorrowsPrior, uint accountBorrows, uint totalBorrows);
    event Liquidate(address indexed sender, address indexed borrower, address indexed liquidator, uint seizeTokens, uint repayAmount, uint accountBorrowsPrior, uint accountBorrows, uint totalBorrows);

    function BORROW_FEE() external pure returns (uint);
    function collateral() external view returns (address);
    function reserveFactor() external view returns (uint);
    function exchangeRateLast() external view returns (uint);
    function borrowIndex() external view returns (uint);
    function totalBorrows() external view returns (uint);
    function borrowAllowance(address owner, address spender) external view returns (uint);
    function borrowBalance(address borrower) external view returns (uint);
    function borrowTracker() external view returns (address);

    function BORROW_PERMIT_TYPEHASH() external pure returns (bytes32);
    function borrowApprove(address spender, uint256 value) external returns (bool);
    function borrowPermit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
    function borrow(address borrower, address receiver, uint borrowAmount, bytes calldata data) external;
    function liquidate(address borrower, address liquidator) external returns (uint seizeTokens);
    function trackBorrow(address borrower) external;

    /*** Borrowable Interest Rate Model ***/

    event AccrueInterest(uint interestAccumulated, uint borrowIndex, uint totalBorrows);
    event CalculateKink(uint kinkRate);
    event CalculateBorrowRate(uint borrowRate);

    function KINK_BORROW_RATE_MAX() external pure returns (uint);
    function KINK_BORROW_RATE_MIN() external pure returns (uint);
    function KINK_MULTIPLIER() external pure returns (uint);
    function borrowRate() external view returns (uint);
    function kinkBorrowRate() external view returns (uint);
    function kinkUtilizationRate() external view returns (uint);
    function adjustSpeed() external view returns (uint);
    function rateUpdateTimestamp() external view returns (uint32);
    function accrualTimestamp() external view returns (uint32);

    function accrueInterest() external;

    /*** Borrowable Setter ***/

    event NewReserveFactor(uint newReserveFactor);
    event NewKinkUtilizationRate(uint newKinkUtilizationRate);
    event NewAdjustSpeed(uint newAdjustSpeed);
    event NewBorrowTracker(address newBorrowTracker);

    function RESERVE_FACTOR_MAX() external pure returns (uint);
    function KINK_UR_MIN() external pure returns (uint);
    function KINK_UR_MAX() external pure returns (uint);
    function ADJUST_SPEED_MIN() external pure returns (uint);
    function ADJUST_SPEED_MAX() external pure returns (uint);

    function _initialize (
        string calldata _name,
        string calldata _symbol,
        address _underlying,
        address _collateral
    ) external;
    function _setReserveFactor(uint newReserveFactor) external;
    function _setKinkUtilizationRate(uint newKinkUtilizationRate) external;
    function _setAdjustSpeed(uint newAdjustSpeed) external;
    function _setBorrowTracker(address newBorrowTracker) external;
}