// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IEVault
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice Interface of the EVault, an EVC enabled lending vault
interface IEVault {
    function initialize(address proxyCreator) external;
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address account) external view returns (uint);
    function allowance(address holder, address spender) external view returns (uint);
    function transfer(address to, uint amount) external returns (bool);
    function transferFrom(address from, address to, uint amount) external returns (bool);
    function approve(address spender, uint amount) external returns (bool);
    function transferFromMax(address from, address to) external returns (bool);

    function asset() external view returns (address);
    function totalAssets() external view returns (uint);
    function convertToAssets(uint shares) external view returns (uint);
    function convertToShares(uint assets) external view returns (uint);

    function maxDeposit(address account) external view returns (uint);
    function previewDeposit(uint assets) external view returns (uint);
    function maxMint(address account) external view returns (uint);
    function previewMint(uint shares) external view returns (uint);
    function maxWithdraw(address owner) external view returns (uint);
    function previewWithdraw(uint assets) external view returns (uint);
    function maxRedeem(address owner) external view returns (uint);
    function previewRedeem(uint shares) external view returns (uint);

    function deposit(uint amount, address receiver) external returns (uint);
    function mint(uint amount, address receiver) external returns (uint);
    function withdraw(uint amount, address receiver, address owner) external returns (uint);
    function redeem(uint amount, address receiver, address owner) external returns (uint);
    
    function accumulatedFees() external view returns (uint);
    function accumulatedFeesAssets() external view returns (uint);
    function creator() external view returns (address);
    function skim(uint amount, address receiver) external returns (uint);
    function totalBorrows() external view returns (uint);
    function totalBorrowsExact() external view returns (uint);
    function cash() external view returns (uint);
    function debtOf(address account) external view returns (uint);
    function debtOfExact(address account) external view returns (uint);
    function interestRate() external view returns (uint);
    function interestAccumulator() external view returns (uint);
    function dToken() external view returns (address);
    function borrow(uint amount, address receiver) external returns (uint);
    function repay(uint amount, address receiver) external returns (uint);
    function repayWithShares(uint amount, address receiver) external returns (uint shares, uint debt);
    function pullDebt(uint amount, address from) external;
    function flashLoan(uint amount, bytes calldata data) external;
    function touch() external;
    function checkLiquidation(address liquidator, address violator, address collateral)
        external
        view
        returns (uint maxRepay, uint maxYield);

    function liquidate(address violator, address collateral, uint repayAssets, uint minYieldBalance) external;

    function accountLiquidity(address account, bool liquidation)
        external
        view
        returns (uint collateralValue, uint liabilityValue);

    function accountLiquidityFull(address account, bool liquidation)
        external
        view
        returns (address[] memory collaterals, uint[] memory collateralValues, uint liabilityValue);

    function disableController() external;
    function checkAccountStatus(address account, address[] calldata collaterals) external view returns (bytes4);
    function checkVaultStatus() external returns (bytes4);
    function balanceTrackerAddress() external view returns (address);
    function balanceForwarderEnabled(address account) external view returns (bool);
    function enableBalanceForwarder() external;
    function disableBalanceForwarder() external; 
    function governorAdmin() external view returns (address);
    function feeReceiver() external view returns (address);
    function interestFee() external view returns (uint16);
    function interestRateModel() external view returns (address);
    function protocolConfigAddress() external view returns (address);
    function protocolFeeShare() external view returns (uint);
    function protocolFeeReceiver() external view returns (address);
    function caps() external view returns (uint16 supplyCap, uint16 borrowCap);
    function LTVBorrow(address collateral) external view returns (uint16);
    function LTVLiquidation(address collateral) external view returns (uint16);

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

    function LTVList() external view returns (address[] memory);
    function maxLiquidationDiscount() external view returns (uint16);
    function liquidationCoolOffTime() external view returns (uint16);
    function hookConfig() external view returns (address hookTarget, uint32 hookedOps);
    function configFlags() external view returns (uint32);
    function EVC() external view returns (address);
    function unitOfAccount() external view returns (address);
    function oracle() external view returns (address);
    function permit2Address() external view returns (address);
    function convertFees() external;
    function setGovernorAdmin(address newGovernorAdmin) external;
    function setFeeReceiver(address newFeeReceiver) external;
    function setLTV(address collateral, uint16 borrowLTV, uint16 liquidationLTV, uint32 rampDuration) external;
    function setMaxLiquidationDiscount(uint16 newDiscount) external;
    function setLiquidationCoolOffTime(uint16 newCoolOffTime) external;
    function setInterestRateModel(address newModel) external;
    function setHookConfig(address newHookTarget, uint32 newHookedOps) external;
    function setConfigFlags(uint32 newConfigFlags) external;
    function setCaps(uint16 supplyCap, uint16 borrowCap) external;
    function setInterestFee(uint16 newFee) external;

    function MODULE_INITIALIZE() external view returns (address);
    function MODULE_TOKEN() external view returns (address);
    function MODULE_VAULT() external view returns (address);
    function MODULE_BORROWING() external view returns (address);
    function MODULE_LIQUIDATION() external view returns (address);
    function MODULE_RISKMANAGER() external view returns (address);
    function MODULE_BALANCE_FORWARDER() external view returns (address);
    function MODULE_GOVERNANCE() external view returns (address);
}