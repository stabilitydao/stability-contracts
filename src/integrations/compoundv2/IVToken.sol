// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Restored from Sonic.0x87C69a8fB7F04b7890F48A1577a83788683A2036
/// @dev https://github.com/EnclaveLabs/enclabs-protocol
interface IVToken {
  error AddReservesFactorFreshCheck(uint256 actualAddAmount);
  error BorrowCashNotAvailable();
  error BorrowFreshnessCheck();
  error DelegateNotApproved();
  error ForceLiquidateBorrowUnauthorized();
  error HealBorrowUnauthorized();
  error InvalidBlocksPerYear();
  error InvalidTimeBasedConfiguration();
  error LiquidateAccrueCollateralInterestFailed(uint256 errorCode);
  error LiquidateCloseAmountIsUintMax();
  error LiquidateCloseAmountIsZero();
  error LiquidateCollateralFreshnessCheck();
  error LiquidateFreshnessCheck();
  error LiquidateLiquidatorIsBorrower();
  error LiquidateSeizeLiquidatorIsBorrower();
  error MintFreshnessCheck();
  error ProtocolSeizeShareTooBig();
  error RedeemFreshnessCheck();
  error RedeemTransferOutNotPossible();
  error ReduceReservesCashNotAvailable();
  error ReduceReservesCashValidation();
  error ReduceReservesFreshCheck();
  error RepayBorrowFreshnessCheck();
  error SetInterestRateModelFreshCheck();
  error SetReserveFactorBoundsCheck();
  error SetReserveFactorFreshCheck();
  error TransferNotAllowed();
  error Unauthorized(
    address sender,
    address calledContract,
    string methodSignature
  );
  error ZeroAddressNotAllowed();
  event AccrueInterest(
    uint256 cashPrior,
    uint256 interestAccumulated,
    uint256 borrowIndex,
    uint256 totalBorrows
  );
  event Approval(
    address indexed owner,
    address indexed spender,
    uint256 amount
  );
  event BadDebtIncreased(
    address indexed borrower,
    uint256 badDebtDelta,
    uint256 badDebtOld,
    uint256 badDebtNew
  );
  event BadDebtRecovered(uint256 badDebtOld, uint256 badDebtNew);
  event Borrow(
    address indexed borrower,
    uint256 borrowAmount,
    uint256 accountBorrows,
    uint256 totalBorrows
  );
  event HealBorrow(
    address indexed payer,
    address indexed borrower,
    uint256 repayAmount
  );
  event Initialized(uint8 version);
  event LiquidateBorrow(
    address indexed liquidator,
    address indexed borrower,
    uint256 repayAmount,
    address indexed vTokenCollateral,
    uint256 seizeTokens
  );
  event Mint(
    address indexed minter,
    uint256 mintAmount,
    uint256 mintTokens,
    uint256 accountBalance
  );
  event NewAccessControlManager(
    address oldAccessControlManager,
    address newAccessControlManager
  );
  event NewComptroller(
    address indexed oldComptroller,
    address indexed newComptroller
  );
  event NewMarketInterestRateModel(
    address indexed oldInterestRateModel,
    address indexed newInterestRateModel
  );
  event NewProtocolSeizeShare(
    uint256 oldProtocolSeizeShareMantissa,
    uint256 newProtocolSeizeShareMantissa
  );
  event NewProtocolShareReserve(
    address indexed oldProtocolShareReserve,
    address indexed newProtocolShareReserve
  );
  event NewReduceReservesBlockDelta(
    uint256 oldReduceReservesBlockOrTimestampDelta,
    uint256 newReduceReservesBlockOrTimestampDelta
  );
  event NewReserveFactor(
    uint256 oldReserveFactorMantissa,
    uint256 newReserveFactorMantissa
  );
  event NewShortfallContract(
    address indexed oldShortfall,
    address indexed newShortfall
  );
  event OwnershipTransferStarted(
    address indexed previousOwner,
    address indexed newOwner
  );
  event OwnershipTransferred(
    address indexed previousOwner,
    address indexed newOwner
  );
  event ProtocolSeize(
    address indexed from,
    address indexed to,
    uint256 amount
  );
  event Redeem(
    address indexed redeemer,
    uint256 redeemAmount,
    uint256 redeemTokens,
    uint256 accountBalance
  );
  event RepayBorrow(
    address indexed payer,
    address indexed borrower,
    uint256 repayAmount,
    uint256 accountBorrows,
    uint256 totalBorrows
  );
  event ReservesAdded(
    address indexed benefactor,
    uint256 addAmount,
    uint256 newTotalReserves
  );
  event SpreadReservesReduced(
    address indexed protocolShareReserve,
    uint256 reduceAmount,
    uint256 newTotalReserves
  );
  event SweepToken(address indexed token);
  event Transfer(address indexed from, address indexed to, uint256 amount);

  function NO_ERROR() external view returns (uint256);

  function acceptOwnership() external;

  function accessControlManager() external view returns (address);

  function accrualBlockNumber() external view returns (uint256);

  function accrueInterest() external returns (uint256);

  function addReserves(uint256 addAmount) external;

  function allowance(address owner, address spender) external view returns (uint256);

  function approve(address spender, uint256 amount) external returns (bool);

  function badDebt() external view returns (uint256);

  function badDebtRecovered(uint256 recoveredAmount_) external;

  function balanceOf(address owner) external view returns (uint256);

  function balanceOfUnderlying(address owner) external returns (uint256);

  function blocksOrSecondsPerYear() external view returns (uint256);

  function borrow(uint256 borrowAmount) external returns (uint256);

  function borrowBalanceCurrent(address account) external returns (uint256);

  function borrowBalanceStored(address account) external view returns (uint256);

  function borrowBehalf(address borrower, uint256 borrowAmount) external returns (uint256);

  function borrowIndex() external view returns (uint256);

  function borrowRatePerBlock() external view returns (uint256);

  function comptroller() external view returns (address);

  function decimals() external view returns (uint8);

  function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);

  function exchangeRateCurrent() external returns (uint256);

  function exchangeRateStored() external view returns (uint256);

  function forceLiquidateBorrow(
    address liquidator,
    address borrower,
    uint256 repayAmount,
    address vTokenCollateral,
    bool skipLiquidityCheck
  ) external;

  function getAccountSnapshot(address account) external view returns (
    uint256 error,
    uint256 vTokenBalance,
    uint256 borrowBalance,
    uint256 exchangeRate
  );

  function getBlockNumberOrTimestamp() external view returns (uint256);

  function getCash() external view returns (uint256);

  function healBorrow(address payer, address borrower, uint256 repayAmount) external;

  function increaseAllowance(address spender, uint256 addedValue) external returns (bool);

  function initialize(
    address underlying_,
    address comptroller_,
    address interestRateModel_,
    uint256 initialExchangeRateMantissa_,
    string memory name_,
    string memory symbol_,
    uint8 decimals_,
    address admin_,
    address accessControlManager_,
    VTokenInterface.RiskManagementInit memory riskManagement,
    uint256 reserveFactorMantissa_
  ) external;

  function interestRateModel() external view returns (address);

  function isTimeBased() external view returns (bool);

  function isVToken() external pure returns (bool);

  function liquidateBorrow(address borrower, uint256 repayAmount, address vTokenCollateral) external returns (uint256);

  function mint(uint256 mintAmount) external returns (uint256);

  function mintBehalf(address minter, uint256 mintAmount) external returns (uint256);

  function name() external view returns (string memory);

  function owner() external view returns (address);

  function pendingOwner() external view returns (address);

  function protocolSeizeShareMantissa() external view returns (uint256);

  function protocolShareReserve() external view returns (address);

  function redeem(uint256 redeemTokens) external returns (uint256);

  function redeemBehalf(address redeemer, uint256 redeemTokens) external returns (uint256);

  function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

  function redeemUnderlyingBehalf(address redeemer, uint256 redeemAmount) external returns (uint256);

  function reduceReserves(uint256 reduceAmount) external;

  function reduceReservesBlockDelta() external view returns (uint256);

  function reduceReservesBlockNumber() external view returns (uint256);

  function renounceOwnership() external;

  function repayBorrow(uint256 repayAmount) external returns (uint256);

  function repayBorrowBehalf(address borrower, uint256 repayAmount) external returns (uint256);

  function reserveFactorMantissa() external view returns (uint256);

  function seize(address liquidator, address borrower, uint256 seizeTokens) external;

  function setAccessControlManager(address accessControlManager_) external;

  function setInterestRateModel(address newInterestRateModel) external;

  function setProtocolSeizeShare(uint256 newProtocolSeizeShareMantissa_) external;

  function setProtocolShareReserve(address protocolShareReserve_) external;

  function setReduceReservesBlockDelta(uint256 _newReduceReservesBlockOrTimestampDelta) external;

  function setReserveFactor(uint256 newReserveFactorMantissa) external;

  function setShortfallContract(address shortfall_) external;

  function shortfall() external view returns (address);

  function supplyRatePerBlock() external view returns (uint256);

  function sweepToken(address token) external;

  function symbol() external view returns (string memory);

  function totalBorrows() external view returns (uint256);

  function totalBorrowsCurrent() external returns (uint256);

  function totalReserves() external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function transfer(address dst, uint256 amount) external returns (bool);

  function transferFrom(address src, address dst, uint256 amount) external returns (bool);

  function transferOwnership(address newOwner) external;

  function underlying() external view returns (address);

  struct RiskManagementInit {
    address shortfall;
    address protocolShareReserve;
  }
}
