// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IImpermaxCollateral {
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Mint(
        address indexed sender,
        address indexed minter,
        uint256 mintAmount,
        uint256 mintTokens
    );
    event NewLiquidationFee(uint256 newLiquidationFee);
    event NewLiquidationIncentive(uint256 newLiquidationIncentive);
    event NewSafetyMargin(uint256 newSafetyMarginSqrt);
    event Redeem(
        address indexed sender,
        address indexed redeemer,
        uint256 redeemAmount,
        uint256 redeemTokens
    );
    event Sync(uint256 totalBalance);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function LIQUIDATION_FEE_MAX() external view returns (uint256);

    function LIQUIDATION_INCENTIVE_MAX() external view returns (uint256);

    function LIQUIDATION_INCENTIVE_MIN() external view returns (uint256);

    function MINIMUM_LIQUIDITY() external view returns (uint256);

    function PERMIT_TYPEHASH() external view returns (bytes32);

    function SAFETY_MARGIN_SQRT_MAX() external view returns (uint256);

    function SAFETY_MARGIN_SQRT_MIN() external view returns (uint256);

    function _initialize(
        string memory _name,
        string memory _symbol,
        address _underlying,
        address _borrowable0,
        address _borrowable1
    ) external;

    function _setFactory() external;

    function _setLiquidationFee(uint256 newLiquidationFee) external;

    function _setLiquidationIncentive(uint256 newLiquidationIncentive) external;

    function _setSafetyMarginSqrt(uint256 newSafetyMarginSqrt) external;

    function accountLiquidity(address borrower) external returns (uint256 liquidity, uint256 shortfall);

    function accountLiquidityAmounts(
        address borrower,
        uint256 amount0,
        uint256 amount1
    ) external returns (uint256 liquidity, uint256 shortfall);

    function allowance(address, address) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function balanceOf(address) external view returns (uint256);

    function borrowable0() external view returns (address);

    function borrowable1() external view returns (address);

    function canBorrow(address borrower, address borrowable, uint256 accountBorrows) external returns (bool);

    function decimals() external view returns (uint8);

    function exchangeRate() external returns (uint256);

    function factory() external view returns (address);

    function flashRedeem(address redeemer, uint256 redeemAmount, bytes memory data) external;

    function getPrices() external returns (uint256 price0, uint256 price1);

    function getTwapPrice112x112() external returns (uint224 twapPrice112x112);

    function liquidationFee() external view returns (uint256);

    function liquidationIncentive() external view returns (uint256);

    function liquidationPenalty() external view returns (uint256);

    function mint(address minter) external returns (uint256 mintTokens);

    function name() external view returns (string memory);

    function nonces(address) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function redeem(address redeemer) external returns (uint256 redeemAmount);

    function safetyMarginSqrt() external view returns (uint256);

    function seize(
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external returns (uint256 seizeTokens);

    function skim(address to) external;

    function symbol() external view returns (string memory);

    function sync() external;

    function tokensUnlocked(address from, uint256 value) external returns (bool);

    function totalBalance() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(address from, address to, uint256 value) external returns (bool);

    function underlying() external view returns (address);
}

