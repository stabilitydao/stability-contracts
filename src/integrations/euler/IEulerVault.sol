// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice Restored from Sonic.0x11f95aaa59F1AD89576c61E3C9Cd24DF1FdCF46f
interface IEulerVault {
  error E_AccountLiquidity();
  error E_AmountTooLargeToEncode();
  error E_BadAddress();
  error E_BadAssetReceiver();
  error E_BadBorrowCap();
  error E_BadCollateral();
  error E_BadFee();
  error E_BadMaxLiquidationDiscount();
  error E_BadSharesOwner();
  error E_BadSharesReceiver();
  error E_BadSupplyCap();
  error E_BorrowCapExceeded();
  error E_CheckUnauthorized();
  error E_CollateralDisabled();
  error E_ConfigAmountTooLargeToEncode();
  error E_ControllerDisabled();
  error E_DebtAmountTooLargeToEncode();
  error E_EmptyError();
  error E_ExcessiveRepayAmount();
  error E_FlashLoanNotRepaid();
  error E_Initialized();
  error E_InsufficientAllowance();
  error E_InsufficientAssets();
  error E_InsufficientBalance();
  error E_InsufficientCash();
  error E_InsufficientDebt();
  error E_InvalidLTVAsset();
  error E_LTVBorrow();
  error E_LTVLiquidation();
  error E_LiquidationCoolOff();
  error E_MinYield();
  error E_NoLiability();
  error E_NoPriceOracle();
  error E_NotController();
  error E_NotHookTarget();
  error E_NotSupported();
  error E_OperationDisabled();
  error E_OutstandingDebt();
  error E_ProxyMetadata();
  error E_Reentrancy();
  error E_RepayTooMuch();
  error E_SelfLiquidation();
  error E_SelfTransfer();
  error E_SupplyCapExceeded();
  error E_TransientState();
  error E_Unauthorized();
  error E_ViolatorLiquidityDeferred();
  error E_ZeroAssets();
  error E_ZeroShares();
  event Approval(
    address indexed owner,
    address indexed spender,
    uint256 value
  );
  event BalanceForwarderStatus(address indexed account, bool status);
  event Borrow(address indexed account, uint256 assets);
  event ConvertFees(
    address indexed sender,
    address indexed protocolReceiver,
    address indexed governorReceiver,
    uint256 protocolShares,
    uint256 governorShares
  );
  event DebtSocialized(address indexed account, uint256 assets);
  event Deposit(
    address indexed sender,
    address indexed owner,
    uint256 assets,
    uint256 shares
  );
  event EVaultCreated(
    address indexed creator,
    address indexed asset,
    address dToken
  );
  event GovSetCaps(uint16 newSupplyCap, uint16 newBorrowCap);
  event GovSetConfigFlags(uint32 newConfigFlags);
  event GovSetFeeReceiver(address indexed newFeeReceiver);
  event GovSetGovernorAdmin(address indexed newGovernorAdmin);
  event GovSetHookConfig(address indexed newHookTarget, uint32 newHookedOps);
  event GovSetInterestFee(uint16 newFee);
  event GovSetInterestRateModel(address newInterestRateModel);
  event GovSetLTV(
    address indexed collateral,
    uint16 borrowLTV,
    uint16 liquidationLTV,
    uint16 initialLiquidationLTV,
    uint48 targetTimestamp,
    uint32 rampDuration
  );
  event GovSetLiquidationCoolOffTime(uint16 newCoolOffTime);
  event GovSetMaxLiquidationDiscount(uint16 newDiscount);
  event InterestAccrued(address indexed account, uint256 assets);
  event Liquidate(
    address indexed liquidator,
    address indexed violator,
    address collateral,
    uint256 repayAssets,
    uint256 yieldBalance
  );
  event PullDebt(address indexed from, address indexed to, uint256 assets);
  event Repay(address indexed account, uint256 assets);
  event Transfer(address indexed from, address indexed to, uint256 value);
  event VaultStatus(
    uint256 totalShares,
    uint256 totalBorrows,
    uint256 accumulatedFees,
    uint256 cash,
    uint256 interestAccumulator,
    uint256 interestRate,
    uint256 timestamp
  );
  event Withdraw(
    address indexed sender,
    address indexed receiver,
    address indexed owner,
    uint256 assets,
    uint256 shares
  );

  function EVC() external view returns (address);

  function LTVBorrow(address collateral) external view returns (uint16);

  function LTVFull(address collateral)
  external
  view
  returns (
    uint16 borrowLTV,
    uint16 liquidationLTV,
    uint16 initialLiquidationLTV,
    uint48 targetTimestamp,
    uint32 rampDuration
  );

  function LTVLiquidation(address collateral) external view returns (uint16);

  function LTVList() external view returns (address[] memory);

  function MODULE_BALANCE_FORWARDER() external view returns (address);

  function MODULE_BORROWING() external view returns (address);

  function MODULE_GOVERNANCE() external view returns (address);

  function MODULE_INITIALIZE() external view returns (address);

  function MODULE_LIQUIDATION() external view returns (address);

  function MODULE_RISKMANAGER() external view returns (address);

  function MODULE_TOKEN() external view returns (address);

  function MODULE_VAULT() external view returns (address);

  function accountLiquidity(address account, bool liquidation)
  external
  view
  returns (uint256 collateralValue, uint256 liabilityValue);

  function accountLiquidityFull(address account, bool liquidation)
  external
  view
  returns (
    address[] memory collaterals,
    uint256[] memory collateralValues,
    uint256 liabilityValue
  );

  function accumulatedFees() external view returns (uint256);

  function accumulatedFeesAssets() external view returns (uint256);

  function allowance(address holder, address spender)
  external
  view
  returns (uint256);

  function approve(address spender, uint256 amount) external returns (bool);

  function asset() external view returns (address);

  function balanceForwarderEnabled(address account)
  external
  view
  returns (bool);

  function balanceOf(address account) external view returns (uint256);

  function balanceTrackerAddress() external view returns (address);

  function borrow(uint256 amount, address receiver)
  external
  returns (uint256);

  function caps() external view returns (uint16 supplyCap, uint16 borrowCap);

  function cash() external view returns (uint256);

  function checkAccountStatus(address account, address[] memory collaterals)
  external
  view
  returns (bytes4);

  function checkLiquidation(
    address liquidator,
    address violator,
    address collateral
  ) external view returns (uint256 maxRepay, uint256 maxYield);

  function checkVaultStatus() external returns (bytes4);

  function configFlags() external view returns (uint32);

  function convertFees() external;

  function convertToAssets(uint256 shares) external view returns (uint256);

  function convertToShares(uint256 assets) external view returns (uint256);

  function creator() external view returns (address);

  function dToken() external view returns (address);

  function debtOf(address account) external view returns (uint256);

  function debtOfExact(address account) external view returns (uint256);

  function decimals() external view returns (uint8);

  function deposit(uint256 amount, address receiver)
  external
  returns (uint256);

  function disableBalanceForwarder() external;

  function disableController() external;

  function enableBalanceForwarder() external;

  function feeReceiver() external view returns (address);

  function flashLoan(uint256 amount, bytes memory data) external;

  function governorAdmin() external view returns (address);

  function hookConfig() external view returns (address, uint32);

  function initialize(address proxyCreator) external;

  function interestAccumulator() external view returns (uint256);

  function interestFee() external view returns (uint16);

  function interestRate() external view returns (uint256);

  function interestRateModel() external view returns (address);

  function liquidate(
    address violator,
    address collateral,
    uint256 repayAssets,
    uint256 minYieldBalance
  ) external;

  function liquidationCoolOffTime() external view returns (uint16);

  function maxDeposit(address account) external view returns (uint256);

  function maxLiquidationDiscount() external view returns (uint16);

  function maxMint(address account) external view returns (uint256);

  function maxRedeem(address owner) external view returns (uint256);

  function maxWithdraw(address owner) external view returns (uint256);

  function mint(uint256 amount, address receiver) external returns (uint256);

  function name() external view returns (string memory);

  function oracle() external view returns (address);

  function permit2Address() external view returns (address);

  function previewDeposit(uint256 assets) external view returns (uint256);

  function previewMint(uint256 shares) external view returns (uint256);

  function previewRedeem(uint256 shares) external view returns (uint256);

  function previewWithdraw(uint256 assets) external view returns (uint256);

  function protocolConfigAddress() external view returns (address);

  function protocolFeeReceiver() external view returns (address);

  function protocolFeeShare() external view returns (uint256);

  function pullDebt(uint256 amount, address from) external;

  function redeem(
    uint256 amount,
    address receiver,
    address owner
  ) external returns (uint256);

  function repay(uint256 amount, address receiver) external returns (uint256);

  function repayWithShares(uint256 amount, address receiver)
  external
  returns (uint256 shares, uint256 debt);

  function setCaps(uint16 supplyCap, uint16 borrowCap) external;

  function setConfigFlags(uint32 newConfigFlags) external;

  function setFeeReceiver(address newFeeReceiver) external;

  function setGovernorAdmin(address newGovernorAdmin) external;

  function setHookConfig(address newHookTarget, uint32 newHookedOps) external;

  function setInterestFee(uint16 newFee) external;

  function setInterestRateModel(address newModel) external;

  function setLTV(
    address collateral,
    uint16 borrowLTV,
    uint16 liquidationLTV,
    uint32 rampDuration
  ) external;

  function setLiquidationCoolOffTime(uint16 newCoolOffTime) external;

  function setMaxLiquidationDiscount(uint16 newDiscount) external;

  function skim(uint256 amount, address receiver) external returns (uint256);

  function symbol() external view returns (string memory);

  function totalAssets() external view returns (uint256);

  function totalBorrows() external view returns (uint256);

  function totalBorrowsExact() external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function touch() external;

  function transfer(address to, uint256 amount) external returns (bool);

  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) external returns (bool);

  function transferFromMax(address from, address to) external returns (bool);

  function unitOfAccount() external view returns (address);

  function viewDelegate() external payable;

  function withdraw(
    uint256 amount,
    address receiver,
    address owner
  ) external returns (uint256);
}

interface Base {
  struct Integrations {
    address evc;
    address protocolConfig;
    address sequenceRegistry;
    address balanceTracker;
    address permit2;
  }
}

interface Dispatch {
  struct DeployedModules {
    address initialize;
    address token;
    address vault;
    address borrowing;
    address liquidation;
    address riskManager;
    address balanceForwarder;
    address governance;
  }
}

