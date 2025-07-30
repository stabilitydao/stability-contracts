// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Restored from Sonic.0xccAdFCFaa71407707fb3dC93D7d83950171aA2c9
/// @dev https://github.com/EnclaveLabs/enclabs-protocol
interface IComptroller {
  error ActionPaused(address market, uint8 action);
  error BorrowActionNotPaused();
  error BorrowCapExceeded(address market, uint256 cap);
  error BorrowCapIsNotZero();
  error CollateralExceedsThreshold(
    uint256 expectedLessThanOrEqualTo,
    uint256 actual
  );
  error CollateralFactorIsNotZero();
  error ComptrollerMismatch();
  error DelegationStatusUnchanged();
  error EnterMarketActionNotPaused();
  error ExitMarketActionNotPaused();
  error InsufficientCollateral(
    uint256 collateralToSeize,
    uint256 availableCollateral
  );
  error InsufficientLiquidity();
  error InsufficientShortfall();
  error InvalidCollateralFactor();
  error InvalidLiquidationThreshold();
  error LiquidateActionNotPaused();
  error MarketAlreadyListed(address market);
  error MarketNotCollateral(address vToken, address user);
  error MarketNotListed(address market);
  error MaxLoopsLimitExceeded(uint256 loopsLimit, uint256 requiredLoops);
  error MinimalCollateralViolated(
    uint256 expectedGreaterThan,
    uint256 actual
  );
  error MintActionNotPaused();
  error NonzeroBorrowBalance();
  error PriceError(address vToken);
  error RedeemActionNotPaused();
  error RepayActionNotPaused();
  error SeizeActionNotPaused();
  error SnapshotError(address vToken, address user);
  error SupplyCapExceeded(address market, uint256 cap);
  error SupplyCapIsNotZero();
  error TooMuchRepay();
  error TransferActionNotPaused();
  error Unauthorized(
    address sender,
    address calledContract,
    string methodSignature
  );
  error UnexpectedSender(address expectedSender, address actualSender);
  error ZeroAddressNotAllowed();
  event ActionPausedMarket(address vToken, uint8 action, bool pauseState);
  event DelegateUpdated(
    address indexed approver,
    address indexed delegate,
    bool approved
  );
  event Initialized(uint8 version);
  event IsForcedLiquidationEnabledUpdated(
    address indexed vToken,
    bool enable
  );
  event MarketEntered(address indexed vToken, address indexed account);
  event MarketExited(address indexed vToken, address indexed account);
  event MarketSupported(address vToken);
  event MarketUnlisted(address indexed vToken);
  event MaxLoopsLimitUpdated(
    uint256 oldMaxLoopsLimit,
    uint256 newmaxLoopsLimit
  );
  event NewAccessControlManager(
    address oldAccessControlManager,
    address newAccessControlManager
  );
  event NewBorrowCap(address indexed vToken, uint256 newBorrowCap);
  event NewCloseFactor(
    uint256 oldCloseFactorMantissa,
    uint256 newCloseFactorMantissa
  );
  event NewCollateralFactor(
    address vToken,
    uint256 oldCollateralFactorMantissa,
    uint256 newCollateralFactorMantissa
  );
  event NewLiquidationIncentive(
    uint256 oldLiquidationIncentiveMantissa,
    uint256 newLiquidationIncentiveMantissa
  );
  event NewLiquidationThreshold(
    address vToken,
    uint256 oldLiquidationThresholdMantissa,
    uint256 newLiquidationThresholdMantissa
  );
  event NewMinLiquidatableCollateral(
    uint256 oldMinLiquidatableCollateral,
    uint256 newMinLiquidatableCollateral
  );
  event NewPriceOracle(address oldPriceOracle, address newPriceOracle);
  event NewPrimeToken(address oldPrimeToken, address newPrimeToken);
  event NewRewardsDistributor(
    address indexed rewardsDistributor,
    address indexed rewardToken
  );
  event NewSupplyCap(address indexed vToken, uint256 newSupplyCap);
  event OwnershipTransferStarted(
    address indexed previousOwner,
    address indexed newOwner
  );
  event OwnershipTransferred(
    address indexed previousOwner,
    address indexed newOwner
  );

  function acceptOwnership() external;

  function accessControlManager() external view returns (address);

  function accountAssets(address, uint256) external view returns (address);

  function actionPaused(address market, uint8 action) external view returns (bool);

  function addRewardsDistributor(address _rewardsDistributor) external;

  function allMarkets(uint256) external view returns (address);

  function approvedDelegates(address, address) external view returns (bool);

  function borrowCaps(address) external view returns (uint256);

  function borrowVerify(address vToken, address borrower, uint256 borrowAmount) external;

  function checkMembership(address account, address vToken) external view returns (bool);

  function closeFactorMantissa() external view returns (uint256);

  function enterMarkets(address[] memory vTokens) external returns (uint256[] memory);

  function exitMarket(address vTokenAddress) external returns (uint256);

  function getAccountLiquidity(address account) external view returns (
    uint256 error,
    uint256 liquidity,
    uint256 shortfall
  );

  function getAllMarkets() external view returns (address[] memory);

  function getAssetsIn(address account) external view returns (address[] memory);

  function getBorrowingPower(address account) external view returns (
    uint256 error,
    uint256 liquidity,
    uint256 shortfall
  );

  function getHypotheticalAccountLiquidity(
    address account,
    address vTokenModify,
    uint256 redeemTokens,
    uint256 borrowAmount
  ) external view returns (
    uint256 error,
    uint256 liquidity,
    uint256 shortfall
  );

  function getRewardDistributors() external view returns (address[] memory);

  function getRewardsByMarket(address vToken) external view returns (
    RewardSpeeds[] memory rewardSpeeds
  );

  function healAccount(address user) external;

  function initialize(uint256 loopLimit, address accessControlManager) external;

  function isComptroller() external pure returns (bool);

  function isForcedLiquidationEnabled(address) external view returns (bool);

  function isMarketListed(address vToken) external view returns (bool);

  function liquidateAccount(address borrower, LiquidationOrder[] memory orders) external;

  function liquidateBorrowVerify(
    address vTokenBorrowed,
    address vTokenCollateral,
    address liquidator,
    address borrower,
    uint256 actualRepayAmount,
    uint256 seizeTokens
  ) external;

  function liquidateCalculateSeizeTokens(
    address vTokenBorrowed,
    address vTokenCollateral,
    uint256 actualRepayAmount
  ) external view returns (uint256 error, uint256 tokensToSeize);

  function liquidationIncentiveMantissa() external view returns (uint256);

  function markets(address) external view returns (
    bool isListed,
    uint256 collateralFactorMantissa,
    uint256 liquidationThresholdMantissa
  );

  function maxLoopsLimit() external view returns (uint256);

  function minLiquidatableCollateral() external view returns (uint256);

  function mintVerify(address vToken, address minter, uint256 actualMintAmount, uint256 mintTokens) external;

  function oracle() external view returns (address);

  function owner() external view returns (address);

  function pendingOwner() external view returns (address);

  function poolRegistry() external view returns (address);

  function preBorrowHook(address vToken, address borrower, uint256 borrowAmount) external;

  function preLiquidateHook(
    address vTokenBorrowed,
    address vTokenCollateral,
    address borrower,
    uint256 repayAmount,
    bool skipLiquidityCheck
  ) external;

  function preMintHook(address vToken, address minter, uint256 mintAmount) external;

  function preRedeemHook(address vToken, address redeemer, uint256 redeemTokens) external;

  function preRepayHook(address vToken, address borrower) external;

  function preSeizeHook(
    address vTokenCollateral,
    address seizerContract,
    address liquidator,
    address borrower
  ) external;

  function preTransferHook(address vToken, address src, address dst, uint256 transferTokens) external;

  function prime() external view returns (address);

  function redeemVerify(address vToken, address redeemer, uint256 redeemAmount, uint256 redeemTokens) external;

  function renounceOwnership() external;

  function repayBorrowVerify(
    address vToken,
    address payer,
    address borrower,
    uint256 actualRepayAmount,
    uint256 borrowerIndex
  ) external;

  function seizeVerify(
    address vTokenCollateral,
    address vTokenBorrowed,
    address liquidator,
    address borrower,
    uint256 seizeTokens
  ) external;

  function setAccessControlManager(address accessControlManager_) external;

  function setActionsPaused(address[] memory marketsList, uint8[] memory actionsList, bool paused) external;

  function setCloseFactor(uint256 newCloseFactorMantissa) external;

  function setCollateralFactor(
    address vToken,
    uint256 newCollateralFactorMantissa,
    uint256 newLiquidationThresholdMantissa
  ) external;

  function setForcedLiquidation(address vTokenBorrowed, bool enable) external;

  function setLiquidationIncentive(uint256 newLiquidationIncentiveMantissa) external;

  function setMarketBorrowCaps(address[] memory vTokens, uint256[] memory newBorrowCaps) external;

  function setMarketSupplyCaps(address[] memory vTokens, uint256[] memory newSupplyCaps) external;

  function setMaxLoopsLimit(uint256 limit) external;

  function setMinLiquidatableCollateral(uint256 newMinLiquidatableCollateral) external;

  function setPriceOracle(address newOracle) external;

  function setPrimeToken(address _prime) external;

  function supplyCaps(address) external view returns (uint256);

  function supportMarket(address vToken) external;

  function transferOwnership(address newOwner) external;

  function transferVerify(address vToken, address src, address dst, uint256 transferTokens) external;

  function unlistMarket(address market) external returns (uint256);

  function updateDelegate(address delegate, bool approved) external;

  function updatePrices(address account) external;

  struct RewardSpeeds {
    address rewardToken;
    uint256 supplySpeed;
    uint256 borrowSpeed;
  }

  struct LiquidationOrder {
    address vTokenCollateral;
    address vTokenBorrowed;
    uint256 repayAmount;
  }
}
