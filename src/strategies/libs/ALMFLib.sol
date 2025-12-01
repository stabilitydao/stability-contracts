// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ALMFCalcLib} from "./ALMFCalcLib.sol";
import {ConstantsLib} from "../../core/libs/ConstantsLib.sol";
import {IAToken} from "../../integrations/aave/IAToken.sol";
import {IAaveAddressProvider} from "../../integrations/aave/IAaveAddressProvider.sol";
import {IAavePriceOracle} from "../../integrations/aave/IAavePriceOracle.sol";
import {IControllable} from "../../interfaces/IControllable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../../interfaces/IFactory.sol";
import {IFarmingStrategy} from "../../interfaces/IFarmingStrategy.sol";
import {ILeverageLendingStrategy} from "../../interfaces/ILeverageLendingStrategy.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IPool} from "../../integrations/aave/IPool.sol";
import {IStrategy} from "../../interfaces/IStrategy.sol";
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {IVaultMainV3} from "../../integrations/balancerv3/IVaultMainV3.sol";
import {IVault} from "../../interfaces/IVault.sol";
import {LeverageLendingLib} from "./LeverageLendingLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StrategyLib} from "./StrategyLib.sol";

library ALMFLib {
    using SafeERC20 for IERC20;

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.AaveLeverageMerklFarmStrategy")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 internal constant AAVE_MERKL_FARM_STRATEGY_STORAGE_LOCATION =
        0x735fb8abe13487f936dfcaad40428cb37101f887b7e375bd6616c095d1050600;

    uint public constant FARM_ADDRESS_LENDING_VAULT_INDEX = 0;
    uint public constant FARM_ADDRESS_BORROWING_VAULT_INDEX = 1;
    uint public constant FARM_ADDRESS_FLASH_LOAN_VAULT_INDEX = 2;

    uint public constant INTEREST_RATE_MODE_VARIABLE = 2;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          DATA TYPES                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.AaveLeverageMerklFarmStrategy
    struct AlmfStrategyStorage {
        /// @dev Deprecated
        uint lastSharePriceInUSD;

        /// @notice Deposit threshold. Amounts less than the threshold are deposited directly without leverage
        mapping(address asset => uint) thresholds;

        /// @notice Last share price used to calculate profit and loss = [total in collateral asset] / vault.totalSupply()
        /// @dev This value is initialized at first claim revenue (not at first deposit)
        uint lastSharePrice;
    }

    event SetThreshold(address asset, uint value);

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

            // supply: assume here that rewards in collateral are not possible
            IPool(IAToken($.lendingVault).POOL())
                .supply(collateralAsset, IERC20(collateralAsset).balanceOf(address(this)), address(this), 0);

            // borrow
            IPool(IAToken($.borrowingVault).POOL())
                .borrow(token, amount + feeAmount, INTEREST_RATE_MODE_VARIABLE, 0, address(this));

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.Withdraw) {
            uint tempCollateralAmount = $.tempCollateralAmount;
            uint swapPriceImpactTolerance0 = $.swapPriceImpactTolerance0;

            // repay debt
            IPool(IAToken($.borrowingVault).POOL()).repay(token, amount, INTEREST_RATE_MODE_VARIABLE, address(this));

            // withdraw
            {
                address lendingVault = $.lendingVault;
                uint collateralAmountTotal = totalCollateral(lendingVault);

                IPool(IAToken(lendingVault).POOL())
                    .withdraw(collateralAsset, Math.min(tempCollateralAmount, collateralAmountTotal), address(this));
            }

            // swap
            _swap(
                platform,
                collateralAsset,
                token,
                ALMFCalcLib.estimateSwapAmount(
                    platform, amount + feeAmount, collateralAsset, token, swapPriceImpactTolerance0, tokenBalance0
                ),
                // Math.min(tempCollateralAmount, StrategyLib.balance(collateralAsset)),
                swapPriceImpactTolerance0
            );

            // explicit error for the case when _estimateSwapAmount gives incorrect amount
            require(
                ALMFCalcLib.balanceWithoutRewards(token, tokenBalance0) >= amount + feeAmount,
                IControllable.InsufficientBalance()
            );

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // swap unnecessary borrow asset back to collateral
            _swap(
                platform,
                token,
                collateralAsset,
                ALMFCalcLib.balanceWithoutRewards(token, tokenBalance0),
                swapPriceImpactTolerance0
            );

            // reset temp vars
            $.tempCollateralAmount = 0;
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.DecreaseLtv) {
            address lendingVault = $.lendingVault;

            // repay
            IPool(IAToken($.borrowingVault).POOL())
                .repay(
                    token,
                    ALMFCalcLib.balanceWithoutRewards(token, tokenBalance0),
                    INTEREST_RATE_MODE_VARIABLE,
                    address(this)
                );

            // withdraw amount
            IPool(IAToken(lendingVault).POOL()).withdraw(collateralAsset, $.tempCollateralAmount, address(this));

            // swap
            _swap(platform, collateralAsset, token, $.tempCollateralAmount, $.swapPriceImpactTolerance1);

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // repay remaining balance
            IPool(IAToken($.borrowingVault).POOL())
                .repay(
                    token,
                    ALMFCalcLib.balanceWithoutRewards(token, tokenBalance0),
                    INTEREST_RATE_MODE_VARIABLE,
                    address(this)
                );

            $.tempCollateralAmount = 0;
        }

        if ($.tempAction == ILeverageLendingStrategy.CurrentAction.IncreaseLtv) {
            // swap
            _swap(
                platform,
                token,
                collateralAsset,
                ALMFCalcLib.balanceWithoutRewards(token, tokenBalance0) * $.increaseLtvParam1
                    / ALMFCalcLib.INTERNAL_PRECISION,
                $.swapPriceImpactTolerance1
            );

            // supply
            IPool(IAToken($.lendingVault).POOL())
                .deposit(collateralAsset, IERC20(collateralAsset).balanceOf(address(this)), address(this), 0);

            // borrow
            IPool(IAToken($.borrowingVault).POOL())
                .borrow(token, amount + feeAmount, INTEREST_RATE_MODE_VARIABLE, 0, address(this));

            // pay flash loan
            IERC20(token).safeTransfer(flashLoanVault, amount + feeAmount);

            // repay not used borrow
            uint tokenBalance = ALMFCalcLib.balanceWithoutRewards(token, tokenBalance0);
            if (tokenBalance != 0) {
                IPool(IAToken($.borrowingVault).POOL())
                    .repay(token, tokenBalance, INTEREST_RATE_MODE_VARIABLE, address(this));
            }
        }

        // ensure that all rewards are still exist on the balance
        require(tokenBalance0 == IERC20(token).balanceOf(address(this)), IControllable.IncorrectBalance());

        _emitLeverageLendingHealth($);

        $.tempAction = ILeverageLendingStrategy.CurrentAction.None;
    }

    function _emitLeverageLendingHealth(ILeverageLendingStrategy.LeverageLendingBaseStorage storage $) internal {
        (uint collateralAmountBase, uint debtAmountBase,,,,) =
            IPool(IAToken($.lendingVault).POOL()).getUserAccountData(address(this));
        uint ltv = ALMFCalcLib.getLtv(collateralAmountBase, debtAmountBase);
        emit ILeverageLendingStrategy.LeverageLendingHealth(ltv, ALMFCalcLib.ltvToLeverage(ltv));
    }

    function receiveFlashLoanBalancerV2(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        address[] memory tokens,
        uint[] memory amounts,
        uint[] memory feeAmounts
    ) external {
        // Flash loan is performed upon deposit and withdrawal
        ALMFLib._receiveFlashLoan(platform, $, tokens[0], amounts[0], feeAmounts[0]);
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
        ALMFLib._receiveFlashLoan(platform, $, token, amount, 0); // assume that flash loan is free, fee is 0

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
        ALMFLib._receiveFlashLoan(platform, $, token, amount, isToken0 ? fee0 : fee1);
    }

    //endregion ------------------------------------- Flash loan

    //region ------------------------------------- Deposit
    /// @notice Deposit {amount} of the collateral asset
    /// @param amount Amount of collateral asset to deposit
    /// @return value Value is calculated as a delta of (total collateral - total debt) in base assets (USDC, 18 decimals)
    function depositAssets(
        address platform_,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IFactory.Farm memory farm,
        uint amount
    ) external returns (uint value) {
        return _depositAssets(platform_, $, farm, amount);
    }

    /// @notice Deposit {amount} of the collateral asset
    /// @param amount Amount of collateral asset to deposit
    /// @return value Value is calculated as a delta of (total collateral - total debt) in base assets (USDC, 18 decimals)
    function _depositAssets(
        address platform_,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IFactory.Farm memory farm,
        uint amount
    ) internal returns (uint value) {
        ALMFCalcLib.StaticData memory data = _getStaticData(platform_, $, farm);
        ALMFCalcLib.State memory state = _getState(data);

        uint valueWas = ALMFCalcLib.collateralToBase(StrategyLib.balance(data.collateralAsset), data) + calcTotal(state);

        uint threshold = _getStorage().thresholds[data.collateralAsset];
        if (amount > threshold) {
            _deposit(platform_, $, data, amount, state);
        } else {
            // tiny amounts are supplied without leverage
            IPool(IAToken(data.lendingVault).POOL()).supply(data.collateralAsset, amount, address(this), 0);
        }

        state = _getState(data); // refresh state after deposit
        uint valueNow = ALMFCalcLib.collateralToBase(StrategyLib.balance(data.collateralAsset), data) + calcTotal(state);

        if (valueNow > valueWas) {
            value = ALMFCalcLib.collateralToBase(amount, data) + (valueNow - valueWas);
        } else {
            value = ALMFCalcLib.collateralToBase(amount, data) - (valueWas - valueNow);
        }

        _ensureLtvValid(state);
    }

    /// @notice Deposit with leverage: if current leverage is above target, first repay debt directly, then deposit with flash loan;
    function _deposit(
        address platform_,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ALMFCalcLib.StaticData memory data,
        uint amountToDeposit,
        ALMFCalcLib.State memory state
    ) internal {
        uint leverage = ALMFCalcLib.getLeverage(state.collateralBase, state.debtBase);
        if (leverage > data.maxTargetLeverage) {
            (uint amountDepositBase, uint amountRepayBase) = ALMFCalcLib.splitDepositAmount(
                ALMFCalcLib.collateralToBase(amountToDeposit, data),
                (data.minTargetLeverage + data.maxTargetLeverage) / 2,
                state.collateralBase,
                state.debtBase,
                data.swapFee18
            );
            bool repayRequired = amountRepayBase > _getStorage().thresholds[data.borrowAsset];
            if (repayRequired) {
                // restore leverage using direct repay
                _directRepay(platform_, data, ALMFCalcLib.baseToCollateral(amountRepayBase, data));
            }
            if (amountDepositBase != 0) {
                if (repayRequired) {
                    state = _getState(data); // refresh state after direct repay
                }
                // deposit remain amount with leverage
                _depositWithFlash($, data, ALMFCalcLib.baseToCollateral(amountDepositBase, data), state);
            }
        } else {
            _depositWithFlash($, data, amountToDeposit, state);
        }
    }

    /// @notice Directly repay debt by swapping a given part of collateral to borrow asset
    function _directRepay(address platform_, ALMFCalcLib.StaticData memory data, uint amountToDeposit) internal {
        // we need to remember balance to exclude possible rewards (provided in borrow asset) from the amount to repay
        uint borrowBalanceBefore = StrategyLib.balance(data.borrowAsset);

        // swap amount to borrow asset
        _swap(
            platform_,
            data.collateralAsset,
            data.borrowAsset,
            amountToDeposit,
            data.swapFee18 * ConstantsLib.DENOMINATOR / 1e18
        );

        // use all balance of borrow asset to repay debt
        address pool = IAToken(data.borrowingVault).POOL();
        uint amountToRepay = StrategyLib.balance(data.borrowAsset) - borrowBalanceBefore;
        if (amountToRepay != 0) {
            IPool(pool).repay(data.borrowAsset, amountToRepay, INTEREST_RATE_MODE_VARIABLE, address(this));
        }
    }

    /// @notice Deposit with flash loan
    function _depositWithFlash(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ALMFCalcLib.StaticData memory data,
        uint amountToDeposit,
        ALMFCalcLib.State memory state
    ) internal {
        uint borrowAmount = _getDepositFlashAmount(amountToDeposit, data, state);
        (address[] memory flashAssets, uint[] memory flashAmounts) =
            _getFlashLoanAmounts(borrowAmount, data.borrowAsset);

        $.tempAction = ILeverageLendingStrategy.CurrentAction.Deposit;
        LeverageLendingLib.requestFlashLoan($, flashAssets, flashAmounts);
    }

    /// @notice Calculate amount to borrow in flash loan for deposit
    /// @param amountToDeposit Amount of collateral asset to deposit
    function _getDepositFlashAmount(
        uint amountToDeposit,
        ALMFCalcLib.StaticData memory data,
        ALMFCalcLib.State memory state
    ) internal pure returns (uint flashAmount) {
        uint targetLeverage = (data.minTargetLeverage + data.maxTargetLeverage) / 2;
        uint amountBase = ALMFCalcLib._collateralToBase(amountToDeposit, data.priceC18, data.decimalsC);
        uint den =
            (targetLeverage
                    * (data.swapFee18 + data.flashFee18)
                    + (1e18 - data.swapFee18)
                    * ALMFCalcLib.INTERNAL_PRECISION) / 1e18;
        uint num = targetLeverage * (state.collateralBase + amountBase - state.debtBase)
            - (state.collateralBase + amountBase) * ALMFCalcLib.INTERNAL_PRECISION;

        // assume here that den > 0; it's safer to revert in other case
        flashAmount = ALMFCalcLib._baseToBorrow(num / den, data.priceB18, data.decimalsB);
    }

    //endregion ------------------------------------- Deposit

    //region ------------------------------------- Withdraw
    /// @notice Withdraw {value} from the strategy to {receiver}
    /// @param value Value to withdraw in base asset (USD, 18 decimals)
    function withdrawAssets(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IFactory.Farm memory farm,
        uint value,
        address receiver
    ) external returns (uint[] memory amountsOut) {
        ALMFCalcLib.StaticData memory data = _getStaticData(platform, $, farm);
        ALMFCalcLib.State memory state = _getState(data);

        uint collateralBalanceBase = ALMFCalcLib.collateralToBase(StrategyLib.balance(data.collateralAsset), data);
        uint valueWas = collateralBalanceBase + calcTotal(state);

        // ---------------------- withdraw from the lending vault - only if amount on the balance is not enough
        if (value > collateralBalanceBase) {
            // it's too dangerous to ask to withdraw (value - state.collateralBalanceStrategy)
            // because current balance is used in multiple places inside receiveFlashLoan
            // so we ask to withdraw full required amount
            _withdrawRequiredAmountOnBalance($, data, state, value);
            state = _getState(data);
        }

        // ---------------------- Transfer required amount to the user
        uint balance = StrategyLib.balance(data.collateralAsset);
        uint valueNow = ALMFCalcLib.collateralToBase(balance, data) + calcTotal(state);

        amountsOut = new uint[](1);
        if (valueWas > valueNow) {
            amountsOut[0] = Math.min(ALMFCalcLib.baseToCollateral(value - (valueWas - valueNow), data), balance);
        } else {
            amountsOut[0] = Math.min(ALMFCalcLib.baseToCollateral(value + (valueNow - valueWas), data), balance);
        }

        // we can have dust amounts of collateral on strategy balance here

        if (receiver != address(this)) {
            IERC20(data.collateralAsset).safeTransfer(receiver, amountsOut[0]);
        }

        _ensureLtvValid(state);
    }

    /// @notice Withdraw required amount on balance as collateral asset
    /// @param value Value to withdraw in base asset (USD, 18 decimals)
    function _withdrawRequiredAmountOnBalance(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ALMFCalcLib.StaticData memory data,
        ALMFCalcLib.State memory state,
        uint value
    ) internal {
        if (0 == state.debtBase) {
            // zero debt, positive supply - we can just withdraw missed amount from the lending pool

            // collateral amount on balance in base asset
            uint balance = StrategyLib.balance(data.collateralAsset);
            uint collateralBalanceBase = ALMFCalcLib.collateralToBase(balance, data);

            // collateral amount required to withdraw from lending pool
            uint amountToWithdraw =
                ALMFCalcLib.baseToCollateral(value > collateralBalanceBase ? value - collateralBalanceBase : 0, data);

            if (amountToWithdraw != 0) {
                IPool(IAToken(data.lendingVault).POOL()).withdraw(data.collateralAsset, amountToWithdraw, address(this));
            }
        } else {
            _withdrawUsingFlash($, data, state, value);
        }
    }

    /// @notice Withdraw required amount of collateral on balance using flash loan
    function _withdrawUsingFlash(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        ALMFCalcLib.StaticData memory data,
        ALMFCalcLib.State memory state,
        uint value
    ) internal {
        uint leverage = ALMFCalcLib.adjustLeverage(
            ALMFCalcLib.getLeverage(state.collateralBase, state.debtBase),
            data.minTargetLeverage,
            data.maxTargetLeverage,
            $.withdrawParam0
        );

        (uint flashAmount, uint collateralToWithdraw) = ALMFCalcLib.calcWithdrawAmounts(value, leverage, data, state);

        if (value == state.collateralBase - state.debtBase) {
            // full withdraw (emergency)
            // we can use flashAmount calculated above but need to override collateralToWithdraw to withdraw fully
            collateralToWithdraw = totalCollateral(data.lendingVault);
        }

        if (flashAmount == 0) {
            // special case: don't use flash, just withdraw required amount from aave and send it to the user
            IPool(IAToken(data.lendingVault).POOL()).withdraw(data.collateralAsset, collateralToWithdraw, address(this));
        } else {
            (address[] memory flashAssets, uint[] memory flashAmounts) =
                _getFlashLoanAmounts(flashAmount, data.borrowAsset);

            $.tempCollateralAmount = collateralToWithdraw;

            $.tempAction = ILeverageLendingStrategy.CurrentAction.Withdraw;
            LeverageLendingLib.requestFlashLoan($, flashAssets, flashAmounts);
        }
    }

    //endregion ------------------------------------- Withdraw

    //region ------------------------------------- View
    /// @notice Calculate total value: collateral - debt in base asset (USD, 18 decimals)
    /// Balance on the strategy is NOT included.
    function calcTotal(ALMFCalcLib.State memory state) internal pure returns (uint totalValue) {
        totalValue = state.collateralBase - state.debtBase;
    }

    /// @notice Get prices of collateral and borrow assets from Aave price oracle in USD, decimals 18
    function getPrices(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $
    ) external view returns (uint collateralPrice, uint borrowPrice) {
        (collateralPrice, borrowPrice) = ALMFLib.getPrices(
            IPool(IAToken($.lendingVault).POOL()).ADDRESSES_PROVIDER(), $.collateralAsset, $.borrowAsset
        );
    }

    /// @notice Get prices of collateral and borrow assets from Aave price oracle in USD, decimals 18
    function getPrices(
        address aaveAddressProvider,
        address collateralAsset,
        address borrowAsset
    ) internal view returns (uint priceC, uint priceB) {
        address[] memory assets = new address[](2);
        assets[0] = collateralAsset;
        assets[1] = borrowAsset;

        uint[] memory prices =
            IAavePriceOracle(IAaveAddressProvider(aaveAddressProvider).getPriceOracle()).getAssetsPrices(assets);
        return (prices[0] * 1e10, prices[1] * 1e10); // Aave prices have 8 decimals, we need 18
    }

    /// @notice Get static data for deposit/withdraw calculations
    function _getStaticData(
        address platform_,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IFactory.Farm memory farm
    ) internal view returns (ALMFCalcLib.StaticData memory data) {
        data.platform = platform_;

        data.collateralAsset = $.collateralAsset;
        data.borrowAsset = $.borrowAsset;
        data.lendingVault = $.lendingVault;
        data.borrowingVault = $.borrowingVault;

        data.addressProvider = IPool(IAToken(data.lendingVault).POOL()).ADDRESSES_PROVIDER();

        data.flashLoanVault = $.flashLoanVault;
        data.flashLoanKind = $.flashLoanKind;

        data.swapFee18 = $.swapPriceImpactTolerance0 * 1e18 / ConstantsLib.DENOMINATOR;
        data.flashFee18 = LeverageLendingLib.getFlashFee18(data.flashLoanVault, data.flashLoanKind);

        data.decimalsC = IERC20Metadata(data.collateralAsset).decimals();
        data.decimalsB = IERC20Metadata(data.borrowAsset).decimals();
        (data.priceC18, data.priceB18) = ALMFLib.getPrices(data.addressProvider, data.collateralAsset, data.borrowAsset);

        (data.minTargetLeverage, data.maxTargetLeverage) = _getFarmLeverageConfig(farm);

        return data;
    }

    /// @return targetMinLeverage Minimum target leverage, INTERNAL_PRECISION
    /// @return targetMaxLeverage Maximum target leverage, INTERNAL_PRECISION
    function _getFarmLeverageConfig(
        IFactory.Farm memory farm
    ) internal pure returns (uint targetMinLeverage, uint targetMaxLeverage) {
        return (ALMFCalcLib.ltvToLeverage(farm.nums[0]), ALMFCalcLib.ltvToLeverage(farm.nums[1]));
    }

    /// @notice Get current state: collateral and debt in base asset (USD, 18 decimals)
    function _getState(address pool_) internal view returns (ALMFCalcLib.State memory state) {
        (uint totalCollateralBase, uint totalDebtBase,,, uint maxLtv, uint healthFactor) =
            IPool(pool_).getUserAccountData(address(this));

        state = ALMFCalcLib.State({
            collateralBase: totalCollateralBase * 1e10,
            debtBase: totalDebtBase * 1e10,
            maxLtv: maxLtv,
            healthFactor: healthFactor
        });
    }

    /// @notice Get current state: collateral and debt in base asset (USD, 18 decimals)
    function _getState(ALMFCalcLib.StaticData memory data) internal view returns (ALMFCalcLib.State memory state) {
        return _getState(IAaveAddressProvider(data.addressProvider).getPool());
    }

    function totalCollateral(address lendingVault) public view returns (uint) {
        return IAToken(lendingVault).balanceOf(address(this));
    }

    /// @dev not optimal by gas, but it's ok for view function
    function health(
        address platform,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IFactory.Farm memory farm
    )
        external
        view
        returns (
            uint ltv,
            uint maxLtv,
            uint leverage,
            uint collateralAmount,
            uint debtAmount,
            uint targetLeveragePercent
        )
    {
        ALMFCalcLib.StaticData memory data = _getStaticData(platform, $, farm);
        IPool pool = IPool(IAToken(data.lendingVault).POOL());

        // Maximum LTV with 4 decimals
        uint collateralAmountBase;
        uint debtAmountBase;
        (collateralAmountBase, debtAmountBase,,, maxLtv,) = pool.getUserAccountData(address(this));

        // convert from aave base (decimals USD, 1e8) to our base asset (USD, 18 decimals)
        collateralAmountBase *= 1e10;
        debtAmountBase *= 1e10;

        // Current amount of collateral asset (strategy asset)
        collateralAmount = ALMFCalcLib.baseToCollateral(collateralAmountBase, data);

        // Current debt of borrowed asset
        debtAmount = ALMFCalcLib.baseToBorrow(debtAmountBase, data);

        // Current LTV with 4 decimals
        ltv = ALMFCalcLib.getLtv(collateralAmountBase, debtAmountBase);

        // Current leverage multiplier with 4 decimals
        leverage = ALMFCalcLib.ltvToLeverage(ltv);

        // targetLeveragePercent Configurable percent of max leverage with 4 decimals
        uint maxLeverage = ALMFCalcLib.ltvToLeverage(maxLtv);
        uint targetLeverage = (data.minTargetLeverage + data.maxTargetLeverage) / 2;
        targetLeveragePercent = targetLeverage * ALMFCalcLib.INTERNAL_PRECISION / maxLeverage;
    }

    function total(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $
    ) internal view returns (uint totalValue) {
        totalValue = calcTotal(_getState(IAToken($.lendingVault).POOL()));
    }

    function previewDepositValue(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        uint[] memory amountsMax
    ) external view returns (uint[] memory amountsConsumed, uint value) {
        amountsConsumed = new uint[](1);
        amountsConsumed[0] = amountsMax[0];

        address collateralAsset = $.collateralAsset;

        // value is [total collateral - total debt] in USD, 18 decimals
        uint price8 = IAavePriceOracle(
                IAaveAddressProvider(IPool(IAToken($.lendingVault).POOL()).ADDRESSES_PROVIDER()).getPriceOracle()
            ).getAssetPrice(collateralAsset);

        value = amountsMax[0] * price8 * 1e10 / (10 ** IERC20Metadata(collateralAsset).decimals());
    }

    //endregion ------------------------------------- View

    //region ------------------------------------- Swap
    function _swap(
        address platform,
        address tokenIn,
        address tokenOut,
        uint amount,
        uint priceImpactTolerance
    ) internal {
        ISwapper swapper = ISwapper(IPlatform(platform).swapper());
        swapper.swap(tokenIn, tokenOut, amount, priceImpactTolerance);
    }

    //endregion ------------------------------------- Swap

    //region ------------------------------------- Rebalance debt
    function rebalanceDebt(
        address platform,
        uint newLtv,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IFactory.Farm memory farm
    ) external returns (uint resultLtv) {
        ALMFCalcLib.StaticData memory data = _getStaticData(platform, $, farm);
        ALMFCalcLib.State memory state = _getState(data);

        // here is the math that works:
        // collateral_value - debt_value = real_TVL
        // debt_value * PRECISION / collateral_value = LTV
        // ---
        // new_collateral_value = real_TVL * PRECISION / (PRECISION - LTV)
        // new_debt_value = new_collateral_value * LTV / PRECISION
        // real_TVL is not changed if current strategy balance of collateral is zero

        uint tvlBase = ALMFCalcLib.collateralToBase(StrategyLib.balance(data.collateralAsset), data) + calcTotal(state);

        uint newCollateralValueBase =
            tvlBase * ALMFCalcLib.INTERNAL_PRECISION / (ALMFCalcLib.INTERNAL_PRECISION - newLtv);
        uint newDebtAmountBase = newCollateralValueBase * newLtv / ALMFCalcLib.INTERNAL_PRECISION;

        uint debtDiff;
        if (newLtv < ALMFCalcLib.getLtv(state.collateralBase, state.debtBase)) {
            // need decrease debt and collateral
            $.tempAction = ILeverageLendingStrategy.CurrentAction.DecreaseLtv;

            debtDiff = ALMFCalcLib.baseToBorrow(state.debtBase - newDebtAmountBase, data);

            $.tempCollateralAmount = (ALMFCalcLib.baseToCollateral(state.collateralBase - newCollateralValueBase, data))
                * $.decreaseLtvParam0 / ALMFCalcLib.INTERNAL_PRECISION;
        } else {
            // need increase debt and collateral
            $.tempAction = ILeverageLendingStrategy.CurrentAction.IncreaseLtv;

            debtDiff = (ALMFCalcLib.baseToBorrow(newDebtAmountBase - state.debtBase, data)) * $.increaseLtvParam0
                / ALMFCalcLib.INTERNAL_PRECISION;
        }

        (address[] memory flashAssets, uint[] memory flashAmounts) = _getFlashLoanAmounts(debtDiff, data.borrowAsset);

        LeverageLendingLib.requestFlashLoan($, flashAssets, flashAmounts);

        $.tempAction = ILeverageLendingStrategy.CurrentAction.None;

        state = _getState(data);
        resultLtv = ALMFCalcLib.getLtv(state.collateralBase, state.debtBase);
    }

    //endregion ------------------------------------- Rebalance debt

    //region ------------------------------------- Real tvl

    /// @notice Calculate real TVL in USD, decimals 18
    function realTvl(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $
    ) public view returns (uint tvl, bool trusted) {
        return _realTvl(_getState(IAToken($.lendingVault).POOL()));
    }

    /// @notice Calculate real TVL in USD, decimals 18
    function _realTvl(ALMFCalcLib.State memory state) internal pure returns (uint tvl, bool trusted) {
        tvl = state.collateralBase - state.debtBase;
        trusted = true;
    }

    /// @notice Calculate real share price as USD18 / vault-shares
    function _realSharePrice(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        address vault_
    ) internal view returns (uint sharePrice, bool trusted) {
        uint __realTvl;
        (__realTvl, trusted) = realTvl($);
        uint totalSupply = IERC20(vault_).totalSupply();
        if (totalSupply != 0) {
            sharePrice = __realTvl * 1e18 / totalSupply;
        }
        return (sharePrice, trusted);
    }

    //endregion ------------------------------------- Real tvl

    //region ------------------------------------- Revenue
    function _getDepositAndBorrowAprs(
        address lendingVault,
        address collateralAsset,
        address borrowAsset
    ) external view returns (uint depositApr, uint borrowApr) {
        IPool pool = IPool(IAToken(lendingVault).POOL());
        IPool.ReserveData memory collateralData = pool.getReserveData(collateralAsset);
        IPool.ReserveData memory borrowData = pool.getReserveData(borrowAsset);

        // liquidityRate and variableBorrowRate are in Ray (1e27)
        // To convert to percentage with 5 decimals (1e5), use:
        // rate(1e27) * 1e5 / 1e27 = rate / 1e22
        depositApr = uint(collateralData.currentLiquidityRate) * ConstantsLib.DENOMINATOR / 1e27;
        borrowApr = uint(borrowData.currentVariableBorrowRate) * ConstantsLib.DENOMINATOR / 1e27;
    }

    function claimRevenue(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        AlmfStrategyStorage storage $a,
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f,
        IStrategy.StrategyBaseStorage storage $base,
        address vault_
    )
        external
        returns (
            address[] memory __assets,
            uint[] memory __amounts,
            address[] memory __rewardAssets,
            uint[] memory __rewardAmounts
        )
    {
        /// @dev New price in collateral asset
        uint newPrice = _sharePrice($, vault_);

        /// @dev Previous price in collateral asset
        uint oldPrice = $a.lastSharePrice;

        if (oldPrice == 0) {
            // first initialization of share price
            // we cannot do it in deposit() because total supply is used for calculation
            $a.lastSharePrice = newPrice;
            oldPrice = newPrice;
        }

        (__assets, __amounts) = _getRevenue($, oldPrice, newPrice, vault_);
        $a.lastSharePrice = newPrice;

        // ---------------------- collect Merkl rewards
        __rewardAssets = $f._rewardAssets;
        uint rwLen = __rewardAssets.length;
        __rewardAmounts = new uint[](rwLen);
        for (uint i; i < rwLen; ++i) {
            // Reward asset can be equal to the borrow asset.
            // The borrow asset is never left on the balance, see _receiveFlashLoan().
            // So, any borrow asset on balance can be considered as a reward.
            __rewardAmounts[i] = StrategyLib.balance(__rewardAssets[i]);
        }

        // This strategy doesn't use $base.total at all
        // but StrategyBase expects it to be set in doHardWork in order to calculate aprCompound
        // so, we set it twice: here (old value) and in _compound (new value)
        $base.total = total($);
    }

    function getRevenue(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        uint oldPrice,
        address vault_
    ) external view returns (address[] memory assets, uint[] memory amounts) {
        uint newPrice = _sharePrice($, vault_);
        return _getRevenue($, oldPrice, newPrice, vault_);
    }

    /// @param oldPrice Previous share price in collateral asset
    /// @param newPrice New share price in collateral asset
    function _getRevenue(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        uint oldPrice,
        uint newPrice,
        address vault_
    ) internal view returns (address[] memory assets, uint[] memory amounts) {
        // assume below that there is only 1 asset - collateral asset
        amounts = new uint[](1);
        assets = new address[](1);

        assets[0] = $.collateralAsset;

        if (newPrice > oldPrice && oldPrice != 0) {
            uint _totalSupply = IVault(vault_).totalSupply();

            // share price already takes into account accumulated interest
            amounts[0] = (newPrice - oldPrice) * _totalSupply / 1e18;
        }
    }

    function liquidateRewards(
        address platform_,
        address exchangeAsset,
        address[] memory rewardAssets_,
        uint[] memory rewardAmounts_,
        uint priceImpactTolerance
    ) external returns (uint earnedExchangeAsset) {
        earnedExchangeAsset = StrategyLib.liquidateRewards(
            platform_, exchangeAsset, rewardAssets_, rewardAmounts_, priceImpactTolerance
        );
    }

    function compound(
        address platform_,
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        IStrategy.StrategyBaseStorage storage $base,
        IFactory.Farm memory farm
    ) external {
        // assume below that there is only 1 asset - collateral asset
        address asset = $.collateralAsset;
        uint amount = StrategyLib.balance(asset);

        if (amount != 0) {
            _depositAssets(platform_, $, farm, amount);
        }

        // This strategy doesn't use $base.total at all
        // but StrategyBase expects it to be set in doHardWork in order to calculate aprCompound
        // so, we set it twice: here (new value) and in _claimRevenue (old value)
        $base.total = total($);
    }

    /// @notice Get share price in collateral asset
    function _sharePrice(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        address vault_
    ) internal view returns (uint sharePrice) {
        uint totalSupply = IERC20(vault_).totalSupply();
        if (totalSupply != 0) {
            address collateralAsset = $.collateralAsset;

            /// @dev Real tvl in USD, decimals 18
            (uint __realTvl,) = realTvl($);

            /// @dev Collateral price from AAVE oracle, decimals 8
            uint collateralPrice8 = IAavePriceOracle(
                    IAaveAddressProvider(IPool(IAToken($.lendingVault).POOL()).ADDRESSES_PROVIDER()).getPriceOracle()
                ).getAssetPrice(collateralAsset);

            /// @dev Real tvl in collateral asset
            uint amount = __realTvl * 1e8 * 10 ** IERC20Metadata(collateralAsset).decimals() / collateralPrice8 / 1e18;

            /// @dev Share price: collateral asset per vault-share, decimals = decimals of collateral asset
            sharePrice = amount * 1e18 / totalSupply;
        }

        return sharePrice;
    }

    //endregion ------------------------------------- Revenue

    //region ----------------------------------- Additional functionality
    /// @notice Set threshold for the asset
    function setThreshold(address asset_, uint threshold_) external {
        _getStorage().thresholds[asset_] = threshold_;

        emit SetThreshold(asset_, threshold_);
    }

    //endregion ----------------------------------- Additional functionality

    //region ------------------------------------- Internal utils
    function _getFlashLoanAmounts(
        uint borrowAmount,
        address borrowAsset
    ) internal pure returns (address[] memory flashAssets, uint[] memory flashAmounts) {
        flashAssets = new address[](1);
        flashAssets[0] = borrowAsset;
        flashAmounts = new uint[](1);
        flashAmounts[0] = borrowAmount;
    }

    function _ensureLtvValid(ALMFCalcLib.State memory state) internal pure {
        if (state.debtBase != 0) {
            uint ltv = ALMFCalcLib.getLtv(state.collateralBase, state.debtBase);
            require(state.healthFactor > 1e18 && ltv < state.maxLtv, IControllable.IncorrectLtv(ltv));
        }
    }

    function _getStorage() internal pure returns (AlmfStrategyStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := AAVE_MERKL_FARM_STRATEGY_STORAGE_LOCATION
        }
    }
    //endregion ------------------------------------- Internal utils
}
