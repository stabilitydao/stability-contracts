// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../lib/forge-std/src/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {ConstantsLib} from "../core/libs/ConstantsLib.sol";
import {StrategyBase} from "./base/StrategyBase.sol";
import {LeverageLendingBase} from "./base/LeverageLendingBase.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {StrategyLib} from "./libs/StrategyLib.sol";
import {SiloLib} from "./libs/SiloLib.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";
import {ILeverageLendingStrategy} from "../interfaces/ILeverageLendingStrategy.sol";
import {ISilo} from "../integrations/silo/ISilo.sol";
import {ISiloConfig} from "../integrations/silo/ISiloConfig.sol";
import {ISiloLens} from "../integrations/silo/ISiloLens.sol";
import {IFlashLoanRecipient} from "../integrations/balancer/IFlashLoanRecipient.sol";
import {IBVault} from "../integrations/balancer/IBVault.sol";

/// @title Silo V2 leverage strategy
/// Changelog:
///   1.1.3: Move depositAssets impl to SiloLib to reduce size, use LeverageLendingBase 1.1.2
///   1.1.2: realApr bugfix
///   1.1.1: use LeverageLendingBase 1.1.1
///   1.1.0: use LeverageLendingBase 1.1.0
/// @author Alien Deployer (https://github.com/a17)
contract SiloLeverageStrategy is LeverageLendingBase, IFlashLoanRecipient {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.1.3";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function initialize(address[] memory addresses, uint[] memory nums, int24[] memory ticks) public initializer {
        if (addresses.length != 6 || nums.length != 0 || ticks.length != 0) {
            revert IControllable.IncorrectInitParams();
        }

        LeverageLendingStrategyBaseInitParams memory params;
        params.platform = addresses[0];
        params.vault = addresses[1];
        params.collateralAsset = IERC4626(addresses[2]).asset();
        params.borrowAsset = IERC4626(addresses[3]).asset();
        params.lendingVault = addresses[2];
        params.borrowingVault = addresses[3];
        params.flashLoanVault = addresses[4];
        params.helper = addresses[5];
        params.targetLeveragePercent = 87_00;
        __LeverageLendingBase_init(params);

        IERC20(params.collateralAsset).forceApprove(params.lendingVault, type(uint).max);
        IERC20(params.borrowAsset).forceApprove(params.borrowingVault, type(uint).max);
        address swapper = IPlatform(params.platform).swapper();
        IERC20(params.collateralAsset).forceApprove(swapper, type(uint).max);
        IERC20(params.borrowAsset).forceApprove(swapper, type(uint).max);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CALLBACKS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IFlashLoanRecipient
    function receiveFlashLoan(
        address[] memory tokens,
        uint[] memory amounts,
        uint[] memory feeAmounts,
        bytes memory /*userData*/
    ) external {
        // Flash loan is performed upon deposit and withdrawal
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        SiloLib.receiveFlashLoan(platform(), $, tokens[0], amounts[0], feeAmounts[0]);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function isHardWorkOnDepositAllowed() external pure returns (bool) {
        return true;
    }

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.SILO_LEVERAGE;
    }

    /// @inheritdoc IStrategy
    function initVariants(address platform_)
        public
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        IFactory.StrategyAvailableInitParams memory params =
            IFactory(IPlatform(platform_).factory()).strategyAvailableInitParams(keccak256(bytes(strategyLogicId())));
        uint len = params.initNums[0];
        variants = new string[](len);
        addresses = new address[](len * 4);
        nums = new uint[](0);
        ticks = new int24[](0);
        for (uint i; i < len; ++i) {
            address collateralAsset = IERC4626(params.initAddresses[i * 2]).asset();
            address borrowAsset = IERC4626(params.initAddresses[i * 2 + 1]).asset();
            variants[i] = _generateDescription(params.initAddresses[i * 2], collateralAsset, borrowAsset);
            addresses[i * 2] = params.initAddresses[i * 2];
            addresses[i * 2 + 1] = params.initAddresses[i * 2 + 1];
            addresses[i * 2 + 2] = params.initAddresses[i * 2 + 2];
            addresses[i * 2 + 3] = params.initAddresses[i * 2 + 3];
        }
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        return _generateDescription($.lendingVault, $.collateralAsset, $.borrowAsset);
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external view override returns (string memory, bool) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        address lendingVault = $.lendingVault;
        uint siloId = ISiloConfig(ISilo(lendingVault).config()).SILO_ID();
        string memory borrowAssetSymbol = IERC20Metadata($.borrowAsset).symbol();
        (,, uint targetLeverage) = SiloLib.getLtvData(lendingVault, $.targetLeveragePercent);
        return (
            string.concat(CommonLib.u2s(siloId), " ", borrowAssetSymbol, " ", _formatLeverageShort(targetLeverage)),
            false
        );
    }

    /// @inheritdoc ILeverageLendingStrategy
    function realTvl() public view returns (uint tvl, bool trusted) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        return SiloLib.realTvl(platform(), $);
    }

    function _realSharePrice() internal view override returns (uint sharePrice, bool trusted) {
        uint _realTvl;
        (_realTvl, trusted) = realTvl();
        uint totalSupply = IERC20(vault()).totalSupply();
        if (totalSupply != 0) {
            sharePrice = _realTvl * 1e18 / totalSupply;
        }
    }

    /// @inheritdoc ILeverageLendingStrategy
    function health()
        public
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
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        return SiloLib.health(platform(), $);
    }

    /// @inheritdoc ILeverageLendingStrategy
    function getSupplyAndBorrowAprs() external view returns (uint supplyApr, uint borrowApr) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        return _getDepositAndBorrowAprs($.helper, $.lendingVault, $.borrowingVault);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   LEVERAGE LENDING BASE                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _rebalanceDebt(uint newLtv) internal override returns (uint resultLtv) {
        (uint ltv, uint maxLtv,, uint collateralAmount,,) = health();

        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        LeverageLendingAddresses memory v = SiloLib.getLeverageLendingAddresses($);

        uint tvlPricedInCollateralAsset = SiloLib.calcTotal(v);

        // here is the math that works:
        // collateral_value - debt_value = real_TVL
        // debt_value * PRECISION / collateral_value = LTV
        // ---
        // collateral_value = real_TVL * PRECISION / (PRECISION - LTV)

        uint newCollateralValue = tvlPricedInCollateralAsset * INTERNAL_PRECISION / (INTERNAL_PRECISION - newLtv);
        address[] memory flashAssets = new address[](1);
        flashAssets[0] = v.collateralAsset;
        uint[] memory flashAmounts = new uint[](1);

        if (newLtv < ltv) {
            $.tempAction = CurrentAction.DecreaseLtv;

            // need decrease debt and collateral
            uint collateralDiff = collateralAmount - newCollateralValue;
            flashAmounts[0] = collateralDiff;
        } else {
            $.tempAction = CurrentAction.IncreaseLtv;

            // need increase debt and collateral
            uint collateralDiff = newCollateralValue - collateralAmount;
            (uint priceCtoB,) = SiloLib.getPrices(v.lendingVault, v.borrowingVault);
            flashAmounts[0] = collateralDiff;
            $.tempBorrowAmount = (flashAmounts[0] * maxLtv / 1e18) * priceCtoB / 1e18 - 2;
        }

        IBVault($.flashLoanVault).flashLoan(address(this), flashAssets, flashAmounts, "");

        $.tempAction = CurrentAction.None;
        (resultLtv,,,,,) = health();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        assets_ = assets();
        amounts_ = new uint[](1);
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        amounts_[0] = SiloLib.totalCollateral($.lendingVault);
    }

    /// @inheritdoc StrategyBase
    function _claimRevenue()
        internal
        override
        returns (
            address[] memory __assets,
            uint[] memory __amounts,
            address[] memory __rewardAssets,
            uint[] memory __rewardAmounts
        )
    {
        __assets = assets();
        __rewardAssets = new address[](0);
        __rewardAmounts = new uint[](0);
        __amounts = new uint[](1);

        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        LeverageLendingAddresses memory v = SiloLib.getLeverageLendingAddresses($);
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();

        uint totalWas = $base.total;

        ISilo(v.lendingVault).accrueInterest();
        ISilo(v.borrowingVault).accrueInterest();

        uint totalNow = StrategyLib.balance(v.collateralAsset) + SiloLib.calcTotal(v);
        if (totalNow > totalWas) {
            __amounts[0] = totalNow - totalWas;
        }
        $base.total = totalNow;

        {
            int earned = int(totalNow) - int(totalWas);
            (uint _realTvl,) = realTvl();
            uint duration = block.timestamp - $base.lastHardWork;
            IPriceReader priceReader = IPriceReader(IPlatform(platform()).priceReader());
            (uint collateralPrice,) = priceReader.getPrice(v.collateralAsset);
            int realEarned = earned * int(collateralPrice) / int(10 ** IERC20Metadata(v.collateralAsset).decimals());
            int realApr = StrategyLib.computeAprInt(_realTvl, realEarned, duration);
            (uint depositApr, uint borrowApr) = _getDepositAndBorrowAprs($.helper, v.lendingVault, v.borrowingVault);
            (uint sharePrice,) = _realSharePrice();
            emit LeverageLendingHardWork(realApr, earned, _realTvl, duration, sharePrice, depositApr, borrowApr);
        }

        (uint ltv,, uint leverage,,,) = health();
        emit LeverageLendingHealth(ltv, leverage);
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax)
        internal
        pure
        override(StrategyBase)
        returns (uint[] memory amountsConsumed, uint value)
    {
        amountsConsumed = new uint[](1);
        amountsConsumed[0] = amountsMax[0];
        value = amountsConsumed[0];
    }

    /// @inheritdoc StrategyBase
    function _depositAssets(uint[] memory amounts, bool /*claimRevenue*/ ) internal override returns (uint value) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        return SiloLib.depositAssets($, $base, assets(), amounts);
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        $.tempAction = CurrentAction.Withdraw;
        LeverageLendingAddresses memory v = SiloLib.getLeverageLendingAddresses($);
        amountsOut = new uint[](1);

        uint valueWas = StrategyLib.balance(v.collateralAsset) + SiloLib.calcTotal(v);

        (uint maxLtv, uint maxLeverage,) = SiloLib.getLtvData(v.lendingVault, $.targetLeveragePercent);

        (uint priceCtoB,) = SiloLib.getPrices(v.lendingVault, v.borrowingVault);

        {
            uint collateralAmountToWithdraw = value * maxLeverage / INTERNAL_PRECISION;
            $.tempCollateralAmount = collateralAmountToWithdraw;
            uint[] memory flashAmounts = new uint[](1);
            flashAmounts[0] = (collateralAmountToWithdraw * maxLtv / 1e18) * priceCtoB / 1e18;
            address[] memory flashAssets = new address[](1);
            flashAssets[0] = $.borrowAsset;
            IBVault($.flashLoanVault).flashLoan(address(this), flashAssets, flashAmounts, "");
        }

        uint valueNow = StrategyLib.balance(v.collateralAsset) + SiloLib.calcTotal(v);

        uint bal = StrategyLib.balance(v.collateralAsset);
        if (valueWas > valueNow) {
            //console.log('withdraw loss', valueWas - valueNow);
            amountsOut[0] = Math.min(value - (valueWas - valueNow), bal);
        } else {
            //console.log('withdraw profit', valueNow - valueWas);
            amountsOut[0] = Math.min(value + (valueNow - valueWas), bal);
        }

        IERC20(v.collateralAsset).safeTransfer(receiver, amountsOut[0]);

        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        $base.total -= value;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _generateDescription(
        address lendingVault,
        address collateralAsset,
        address borrowAsset
    ) internal view returns (string memory) {
        uint siloId = ISiloConfig(ISilo(lendingVault).config()).SILO_ID();
        return string.concat(
            "Supply ",
            IERC20Metadata(collateralAsset).symbol(),
            " and borrow ",
            IERC20Metadata(borrowAsset).symbol(),
            " on Silo V2 market ",
            CommonLib.u2s(siloId),
            " with leverage looping"
        );
    }

    function _formatLeverageShort(uint amount) internal pure returns (string memory) {
        uint intAmount = amount / 100_00;
        uint decimalAmount = (amount - intAmount * 100_00) / 10_00;
        return string.concat("x", CommonLib.u2s(intAmount), ".", CommonLib.u2s(decimalAmount));
    }

    function _getDepositAndBorrowAprs(
        address lens,
        address lendingVault,
        address debtVault
    ) internal view returns (uint depositApr, uint borrowApr) {
        depositApr = ISiloLens(lens).getDepositAPR(lendingVault) * ConstantsLib.DENOMINATOR / 1e18;
        borrowApr = ISiloLens(lens).getBorrowAPR(debtVault) * ConstantsLib.DENOMINATOR / 1e18;
    }
}
