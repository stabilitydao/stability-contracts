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
    string public constant VERSION = "1.0.0";

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

    function getFlashLoanVault() external view returns (address flashLoanVault, uint flashLoanKind) {
        LiquidationBotLib.LiquidationBotStorage storage $ = LiquidationBotLib.getLiquidationBotStorage();
        return ($.flashLoanVault, $.flashLoanKind);
    }

    /// @notice Info: what assets the user has, what is the balance of aTokens, stable and variable debt
    function getUserAssetInfo(address aavePool, address user) external view returns (UserAssetInfo[] memory) {
        return LiquidationBotLib.getUserAssetInfo(aavePool, user);
    }

    /// @notice Info: current state of the user account
    function getUserAccountData(address aavePool, address user) external view returns (UserAccountData memory) {
        return LiquidationBotLib.getUserAccountData(LiquidationBotLib.getAaveContracts(aavePool), user);
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
    function setFlashLoanVault(address flashLoanVault, uint flashLoanKind) external onlyMultisig {
        LiquidationBotLib.setFlashLoanVault(flashLoanVault, flashLoanKind);
    }

    /// @inheritdoc ILiquidationBot
    function setPriceImpactTolerance(uint priceImpactTolerance_) external onlyMultisig {
        LiquidationBotLib.setPriceImpactTolerance(priceImpactTolerance_);
    }

    /// @inheritdoc ILiquidationBot
    function setProfitTarget(address profitTarget_) external onlyMultisig {
        LiquidationBotLib.setProfitTarget(profitTarget_);
    }

    /// @inheritdoc ILiquidationBot
    function changeWhitelist(address operator_, bool add_) external onlyMultisig {
        LiquidationBotLib.changeWhitelist(operator_, add_);
    }

    //endregion ----------------------------------- Restricted actions

    //region ----------------------------------- Actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      Actions                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    //endregion ----------------------------------- Actions

    /// @inheritdoc ILiquidationBot
    function liquidate(address aavePool, address[] memory users) external onlyWhitelisted {
        LiquidationBotLib.liquidate(aavePool, users);
    }
}
