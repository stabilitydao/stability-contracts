// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IPool {
  function mintUnbacked(
    address asset,
    uint amount,
    address onBehalfOf,
    uint16 referralCode
  ) external;

  function backUnbacked(address asset, uint amount, uint fee) external returns (uint);

  function supply(address asset, uint amount, address onBehalfOf, uint16 referralCode) external;

  function supplyWithPermit(
    address asset,
    uint amount,
    address onBehalfOf,
    uint16 referralCode,
    uint deadline,
    uint8 permitV,
    bytes32 permitR,
    bytes32 permitS
  ) external;

  function withdraw(address asset, uint amount, address to) external returns (uint);

  function borrow(
    address asset,
    uint amount,
    uint interestRateMode,
    uint16 referralCode,
    address onBehalfOf
  ) external;

  function repay(
    address asset,
    uint amount,
    uint interestRateMode,
    address onBehalfOf
  ) external returns (uint);

  function repayWithPermit(
    address asset,
    uint amount,
    uint interestRateMode,
    address onBehalfOf,
    uint deadline,
    uint8 permitV,
    bytes32 permitR,
    bytes32 permitS
  ) external returns (uint);

  function repayWithATokens(
    address asset,
    uint amount,
    uint interestRateMode
  ) external returns (uint);

  function swapBorrowRateMode(address asset, uint interestRateMode) external;

  function rebalanceStableBorrowRate(address asset, address user) external;

  function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;

  function liquidationCall(
    address collateralAsset,
    address debtAsset,
    address user,
    uint debtToCover,
    bool receiveAToken
  ) external;

  function flashLoan(
    address receiverAddress,
    address[] calldata assets,
    uint[] calldata amounts,
    uint[] calldata interestRateModes,
    address onBehalfOf,
    bytes calldata params,
    uint16 referralCode
  ) external;

  function flashLoanSimple(
    address receiverAddress,
    address asset,
    uint amount,
    bytes calldata params,
    uint16 referralCode
  ) external;

  function getUserAccountData(
    address user
  )
    external
    view
    returns (
      uint totalCollateralBase,
      uint totalDebtBase,
      uint availableBorrowsBase,
      uint currentLiquidationThreshold,
      uint ltv,
      uint healthFactor
    );

  function initReserve(
    address asset,
    address aTokenAddress,
    address stableDebtAddress,
    address variableDebtAddress,
    address interestRateStrategyAddress
  ) external;

  function dropReserve(address asset) external;

  function setReserveInterestRateStrategyAddress(
    address asset,
    address rateStrategyAddress
  ) external;

  function getReserveNormalizedIncome(address asset) external view returns (uint);

  function getReserveNormalizedVariableDebt(address asset) external view returns (uint);

  function finalizeTransfer(
    address asset,
    address from,
    address to,
    uint amount,
    uint balanceFromBefore,
    uint balanceToBefore
  ) external;

  function getReservesList() external view returns (address[] memory);

  function updateBridgeProtocolFee(uint bridgeProtocolFee) external;

  function updateFlashloanPremiums(
    uint128 flashLoanPremiumTotal,
    uint128 flashLoanPremiumToProtocol
  ) external;

  function setUserEMode(uint8 categoryId) external;

  function getUserEMode(address user) external view returns (uint);

  function resetIsolationModeTotalDebt(address asset) external;

  function MAX_STABLE_RATE_BORROW_SIZE_PERCENT() external view returns (uint);

  function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint128);

  function BRIDGE_PROTOCOL_FEE() external view returns (uint);

  function FLASHLOAN_PREMIUM_TO_PROTOCOL() external view returns (uint128);

  function MAX_NUMBER_RESERVES() external view returns (uint16);

  function mintToTreasury(address[] calldata assets) external;

  function rescueTokens(address token, address to, uint amount) external;

  function deposit(address asset, uint amount, address onBehalfOf, uint16 referralCode) external;
}