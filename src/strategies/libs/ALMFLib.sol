// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IControllable} from "../../interfaces/IControllable.sol";
import {ILeverageLendingStrategy} from "../../interfaces/ILeverageLendingStrategy.sol";
import {IFlashLoanRecipient} from "../integrations/balancer/IFlashLoanRecipient.sol";
import {IVaultMainV3} from "../integrations/balancerv3/IVaultMainV3.sol";
import {IUniswapV3FlashCallback} from "../integrations/uniswapv3/IUniswapV3FlashCallback.sol";
import {IAlgebraFlashCallback} from "../integrations/algebrav4/callback/IAlgebraFlashCallback.sol";
import {IBalancerV3FlashCallback} from "../integrations/balancerv3/IBalancerV3FlashCallback.sol";


library ALMFLib {
    uint public constant FARM_ADDRESS_LENDING_VAULT_INDEX = 0;
    uint public constant FARM_ADDRESS_BORROWING_VAULT_INDEX = 1;
    uint public constant FARM_ADDRESS_FLASH_LOAN_VAULT_INDEX = 2;


    //region ------------------------------------- Flash loan
    /// @notice token Borrow asset
    /// @notice amount Flash loan amount in borrow asset
    function _receiveFlashLoan(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        address token,
        uint amount,
        uint feeAmount
    ) internal {
        address collateralAsset = $.collateralAsset;
        address flashLoanVault = $.flashLoanVault;
        require(msg.sender == flashLoanVault, IControllable.IncorrectMsgSender());

        // Reward asset can be equal to the borrow asset. Rewards can be transferred to the strategy at any moment.
        // If any borrow asset is on the balance before taking flash loan it can be only rewards.
        // All rewards are processed by hardwork and cannot be used before hardwork.
        // So, we need to keep reward amount on balance after exit this function.
        uint tokenBalance0 = IERC20(token).balanceOf(address(this));
        tokenBalance0 = tokenBalance0 > amount ? tokenBalance0 - amount : 0;

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.Deposit) {
            // swap
            _swap(platform, token, collateralAsset, amount, $.swapPriceImpactTolerance0);

            // supply
            ISilo($.lendingVault)
            .deposit(
                IERC20(collateralAsset).balanceOf(address(this)), address(this), ISilo.CollateralType.Collateral
            );

            // borrow
            ISilo($.borrowingVault).borrow(amount + feeAmount, address(this), address(this));

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.Withdraw) {
            uint tempCollateralAmount = $.tempCollateralAmount;
            uint swapPriceImpactTolerance0 = $.swapPriceImpactTolerance0;

            // repay debt
            ISilo($.borrowingVault).repay(amount, address(this));

            // withdraw
            {
                address lendingVault = $.lendingVault;
                uint collateralAmountTotal = totalCollateral(lendingVault);
                collateralAmountTotal -= collateralAmountTotal / 1000;

                ISilo(lendingVault)
                .withdraw(
                    Math.min(tempCollateralAmount, collateralAmountTotal),
                    address(this),
                    address(this),
                    ISilo.CollateralType.Collateral
                );
            }

            // swap
            _swap(
                platform,
                collateralAsset,
                token,
                _estimateSwapAmount(
                    platform, amount + feeAmount, collateralAsset, token, swapPriceImpactTolerance0, tokenBalance0
                ),
                // Math.min(tempCollateralAmount, StrategyLib.balance(collateralAsset)),
                swapPriceImpactTolerance0
            );

            // explicit error for the case when _estimateSwapAmount gives incorrect amount
            require(
                _balanceWithoutRewards(token, tokenBalance0) >= amount + feeAmount, IControllable.InsufficientBalance()
            );

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // swap unnecessary borrow asset
            _swap(
                platform,
                token,
                collateralAsset,
                _balanceWithoutRewards(token, tokenBalance0),
                swapPriceImpactTolerance0
            );

            // reset temp vars
            $.tempCollateralAmount = 0;
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.DecreaseLtv) {
            address lendingVault = $.lendingVault;

            // repay
            ISilo($.borrowingVault).repay(_balanceWithoutRewards(token, tokenBalance0), address(this));

            // withdraw amount
            ISilo(lendingVault)
            .withdraw($.tempCollateralAmount, address(this), address(this), ISilo.CollateralType.Collateral);

            // swap
            _swap(platform, collateralAsset, token, $.tempCollateralAmount, $.swapPriceImpactTolerance1);

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // repay remaining balance
            ISilo($.borrowingVault).repay(_balanceWithoutRewards(token, tokenBalance0), address(this));

            $.tempCollateralAmount = 0;
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.IncreaseLtv) {
            uint tempCollateralAmount = $.tempCollateralAmount;

            // swap
            _swap(
                platform,
                token,
                collateralAsset,
                _balanceWithoutRewards(token, tokenBalance0) * $.increaseLtvParam1 / INTERNAL_PRECISION,
                $.swapPriceImpactTolerance1
            );

            // supply
            ISilo($.lendingVault)
            .deposit(
                _getLimitedAmount(IERC20(collateralAsset).balanceOf(address(this)), tempCollateralAmount),
                address(this),
                ISilo.CollateralType.Collateral
            );

            // borrow
            ISilo($.borrowingVault).borrow(amount + feeAmount, address(this), address(this));

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // repay not used borrow
            uint tokenBalance = _balanceWithoutRewards(token, tokenBalance0);
            if (tokenBalance != 0) {
                ISilo($.borrowingVault).repay(tokenBalance, address(this));
            }

            // reset temp vars
            if (tempCollateralAmount != 0) {
                $.tempCollateralAmount = 0;
            }
        }

        // ensure that all rewards are still exist on the balance
        require(tokenBalance0 == IERC20(token).balanceOf(address(this)), IControllable.IncorrectBalance());

        (uint ltv,, uint leverage,,,) = health(platform, $);
        emit ILeverageLendingStrategy.LeverageLendingHealth(ltv, leverage);

        $.tempAction = ILeverageLendingStrategy.CurrentAction.None;
    }

    function receiveFlashLoanBalancerV2(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        address[] memory tokens,
        uint[] memory amounts,
        uint[] memory feeAmounts
    ) external {
        // Flash loan is performed upon deposit and withdrawal
        SiloALMFLib._receiveFlashLoan(platform, $, tokens[0], amounts[0], feeAmounts[0]);
    }

    function receiveFlashLoanV3(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        address token,
        uint amount
    ) external {
        // sender is vault, it's checked inside receiveFlashLoan
        // we can use msg.sender below but $.flashLoanVault looks more safe
        IVaultMainV3 vault = IVaultMainV3(payable($.flashLoanVault));

        // ensure that the vault has available amount
        require(IERC20(token).balanceOf(address(vault)) >= amount, IControllable.InsufficientBalance());

        // receive flash loan from the vault
        vault.sendTo(token, address(this), amount);

        // Flash loan is performed upon deposit and withdrawal
        SiloALMFLib._receiveFlashLoan(platform, $, token, amount, 0); // assume that flash loan is free, fee is 0

        // return flash loan back to the vault
        // assume that the amount was transferred back to the vault inside receiveFlashLoan()
        // we need only to register this transferring
        vault.settle(token, amount);
    }

    function uniswapV3FlashCallback(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        uint fee0,
        uint fee1,
        bytes calldata userData
    ) external {
        // sender is the pool, it's checked inside receiveFlashLoan
        (address token, uint amount, bool isToken0) = abi.decode(userData, (address, uint, bool));
        SiloALMFLib._receiveFlashLoan(platform, $, token, amount, isToken0 ? fee0 : fee1);
    }

    //endregion ------------------------------------- Flash loan

}