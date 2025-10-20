// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Controllable} from "../core/base/Controllable.sol";
import {ILiquidationBot} from "../interfaces/ILiquidationBot.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IVaultMainV3} from "../integrations/balancerv3/IVaultMainV3.sol";
import {LiquidationBotLib} from "./libs/LiquidationBotLib.sol";
import {IFlashLoanRecipient} from "../integrations/balancer/IFlashLoanRecipient.sol";
import {IUniswapV3FlashCallback} from "../integrations/uniswapv3/IUniswapV3FlashCallback.sol";
import {IAlgebraFlashCallback} from "../integrations/algebrav4/callback/IAlgebraFlashCallback.sol";
import {IBalancerV3FlashCallback} from "../integrations/balancerv3/IBalancerV3FlashCallback.sol";

/// @notice Liquidation bot for AAVE 3.0.2
/// Changelog:
/// 1.1.0 - add liquidation() with explicit target health factor, replace multisig restrictions with operator
contract LiquidationBot is
    Controllable,
    ILiquidationBot,
    IFlashLoanRecipient,
    IUniswapV3FlashCallback,
    IBalancerV3FlashCallback,
    IAlgebraFlashCallback
{
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.1.0";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc ILiquidationBot
    function initialize(address platform_) public initializer {
        __Controllable_init(platform_);
    }

    modifier onlyWhitelisted() {
        require(whitelisted(msg.sender), LiquidationBotLib.NotWhitelisted());
        _;
    }

    //region ----------------------------------- View
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc ILiquidationBot
    function whitelisted(address operator_) public view returns (bool) {
        if (IPlatform(platform()).multisig() == operator_) {
            return true;
        }

        LiquidationBotLib.LiquidationBotStorage storage $ = LiquidationBotLib.getLiquidationBotStorage();
        return $.whitelistOperators[operator_];
    }

    /// @inheritdoc ILiquidationBot
    function priceImpactTolerance() external view returns (uint _priceImpactTolerance) {
        LiquidationBotLib.LiquidationBotStorage storage $ = LiquidationBotLib.getLiquidationBotStorage();
        return LiquidationBotLib.priceImpactTolerance($);
    }

    /// @inheritdoc ILiquidationBot
    function profitTarget() external view returns (address) {
        LiquidationBotLib.LiquidationBotStorage storage $ = LiquidationBotLib.getLiquidationBotStorage();
        return $.profitTarget;
    }

    /// @inheritdoc ILiquidationBot
    function getFlashLoanVault() external view returns (address flashLoanVault, uint flashLoanKind) {
        LiquidationBotLib.LiquidationBotStorage storage $ = LiquidationBotLib.getLiquidationBotStorage();
        return ($.flashLoanVault, $.flashLoanKind);
    }

    /// @inheritdoc ILiquidationBot
    function getUserAssetInfo(address aavePool, address user) external view returns (UserAssetInfo[] memory) {
        return LiquidationBotLib.getUserAssetInfo(aavePool, user);
    }

    /// @inheritdoc ILiquidationBot
    function getUserAccountData(address aavePool, address user) external view returns (UserAccountData memory) {
        return LiquidationBotLib.getUserAccountData(LiquidationBotLib.getAaveContracts(aavePool), user);
    }

    /// @inheritdoc ILiquidationBot
    function getCollateralToReceive(
        address aavePool,
        address collateralAsset_,
        address debtAsset_,
        uint collateralAmount_,
        uint repayAmount_
    ) external view returns (uint collateralToReceive) {
        return LiquidationBotLib.getCollateralToReceive(
            LiquidationBotLib.getAaveContracts(aavePool), collateralAsset_, debtAsset_, collateralAmount_, repayAmount_
        );
    }

    /// @inheritdoc ILiquidationBot
    function getRepayAmount(
        address aavePool,
        address collateralAsset_,
        address debtAsset_,
        ILiquidationBot.UserAccountData memory userAccountData_,
        uint targetHealthFactor_
    ) external view returns (uint repayAmount) {
        return LiquidationBotLib._getRepayAmount(
            LiquidationBotLib.getAaveContracts(aavePool),
            collateralAsset_,
            debtAsset_,
            userAccountData_,
            targetHealthFactor_
        );
    }

    /// @inheritdoc ILiquidationBot
    function isWrappedMetaVault(address wrappedMetaVault_) external view returns (bool) {
        LiquidationBotLib.LiquidationBotStorage storage $ = LiquidationBotLib.getLiquidationBotStorage();
        return $.wrappedMetaVaults[wrappedMetaVault_] != 0;
    }

    /// @inheritdoc ILiquidationBot
    function targetHealthFactor() external view returns (uint) {
        LiquidationBotLib.LiquidationBotStorage storage $ = LiquidationBotLib.getLiquidationBotStorage();
        return $.targetHealthFactor;
    }

    //endregion ----------------------------------- View

    //region ----------------------------------- Flash loan
    /// @inheritdoc IFlashLoanRecipient
    /// @dev Support of FLASH_LOAN_KIND_BALANCER_V2
    function receiveFlashLoan(
        address[] memory tokens,
        uint[] memory amounts,
        uint[] memory feeAmounts,
        bytes memory userData
    ) external {
        // Flash loan is performed upon deposit and withdrawal
        LiquidationBotLib.LiquidationBotStorage storage $ = LiquidationBotLib.getLiquidationBotStorage();
        LiquidationBotLib.receiveFlashLoan(platform(), $, tokens[0], amounts[0], feeAmounts[0], userData);
    }

    /// @inheritdoc IBalancerV3FlashCallback
    function receiveFlashLoanV3(address token, uint amount, bytes memory userData) external {
        // sender is vault, it's checked inside receiveFlashLoan
        // we can use msg.sender below but $.flashLoanVault looks more safe
        LiquidationBotLib.LiquidationBotStorage storage $ = LiquidationBotLib.getLiquidationBotStorage();
        IVaultMainV3 vault = IVaultMainV3(payable($.flashLoanVault));

        // ensure that the vault has available amount
        require(IERC20(token).balanceOf(address(vault)) >= amount, IControllable.InsufficientBalance());

        // receive flash loan from the vault
        vault.sendTo(token, address(this), amount);

        // Flash loan is performed upon deposit and withdrawal
        LiquidationBotLib.receiveFlashLoan(platform(), $, token, amount, 0, userData); // assume that flash loan is free, fee is 0

        // return flash loan back to the vault
        // assume that the amount was transferred back to the vault inside receiveFlashLoan()
        // we need only to register this transferring
        //slither-disable-next-line unused-return
        vault.settle(token, amount);
    }

    /// @inheritdoc IUniswapV3FlashCallback
    function uniswapV3FlashCallback(uint fee0, uint fee1, bytes calldata userData) external {
        // sender is the pool, it's checked inside receiveFlashLoan
        (address token, uint amount, bool isToken0, bytes memory data) =
            abi.decode(userData, (address, uint, bool, bytes));

        LiquidationBotLib.LiquidationBotStorage storage $ = LiquidationBotLib.getLiquidationBotStorage();
        LiquidationBotLib.receiveFlashLoan(platform(), $, token, amount, isToken0 ? fee0 : fee1, data);
    }

    function algebraFlashCallback(uint fee0, uint fee1, bytes calldata userData) external {
        // sender is the pool, it's checked inside receiveFlashLoan
        (address token, uint amount, bool isToken0, bytes memory data) =
            abi.decode(userData, (address, uint, bool, bytes));

        LiquidationBotLib.LiquidationBotStorage storage $ = LiquidationBotLib.getLiquidationBotStorage();
        LiquidationBotLib.receiveFlashLoan(platform(), $, token, amount, isToken0 ? fee0 : fee1, data);
    }

    //endregion ----------------------------------- Flash loan

    //region ----------------------------------- Restricted actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc ILiquidationBot
    function setFlashLoanVault(address flashLoanVault, uint flashLoanKind) external onlyOperator {
        LiquidationBotLib.setFlashLoanVault(flashLoanVault, flashLoanKind);
    }

    /// @inheritdoc ILiquidationBot
    function setPriceImpactTolerance(uint priceImpactTolerance_) external onlyOperator {
        LiquidationBotLib.setPriceImpactTolerance(priceImpactTolerance_);
    }

    /// @inheritdoc ILiquidationBot
    function setProfitTarget(address profitTarget_) external onlyMultisig {
        LiquidationBotLib.setProfitTarget(profitTarget_);
    }

    /// @inheritdoc ILiquidationBot
    function changeWhitelist(address operator_, bool add_) external onlyOperator {
        LiquidationBotLib.changeWhitelist(operator_, add_);
    }

    /// @inheritdoc ILiquidationBot
    function changeWrappedMetaVault(address wrappedMetaVault_, bool add_) external onlyOperator {
        LiquidationBotLib.changeWrappedMetaVault(wrappedMetaVault_, add_);
    }

    /// @inheritdoc ILiquidationBot
    function setTargetHealthFactor(uint targetHealthFactor_) external onlyOperator {
        LiquidationBotLib.setTargetHealthFactor(targetHealthFactor_);
    }

    //endregion ----------------------------------- Restricted actions

    //region ----------------------------------- Actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      Actions                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    //endregion ----------------------------------- Actions

    /// @inheritdoc ILiquidationBot
    function liquidate(address aavePool, address[] memory users) external onlyWhitelisted {
        LiquidationBotLib.AaveContracts memory ac = LiquidationBotLib.getAaveContracts(aavePool);
        LiquidationBotLib.liquidate(ac, users, type(uint).max);
    }

    /// @inheritdoc ILiquidationBot
    function liquidate(address aavePool, address[] memory users, uint healthFactor) external onlyWhitelisted {
        LiquidationBotLib.AaveContracts memory ac = LiquidationBotLib.getAaveContracts(aavePool);
        LiquidationBotLib.liquidate(ac, users, healthFactor);
    }

    /// @inheritdoc ILiquidationBot
    function liquidate(
        address aavePool,
        address[] memory users,
        address debtAsset,
        uint[] memory debtToCover
    ) external onlyWhitelisted {
        LiquidationBotLib.AaveContracts memory ac = LiquidationBotLib.getAaveContracts(aavePool);
        LiquidationBotLib.liquidate(ac, users, debtAsset, debtToCover);
    }
}
