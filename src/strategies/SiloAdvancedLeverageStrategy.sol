// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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
import {SiloAdvancedLib} from "./libs/SiloAdvancedLib.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {ILeverageLendingStrategy} from "../interfaces/ILeverageLendingStrategy.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";
import {ISilo} from "../integrations/silo/ISilo.sol";
import {ISiloConfig} from "../integrations/silo/ISiloConfig.sol";
import {ISiloLens} from "../integrations/silo/ISiloLens.sol";
import {IFlashLoanRecipient} from "../integrations/balancer/IFlashLoanRecipient.sol";
import {IBVault} from "../integrations/balancer/IBVault.sol";

/// @title Silo V2 advanced leverage strategy
/// Changelog:
///   1.1.2: realApr bugfix, emergency withdraw fix
///   1.1.1: use LeverageLendingBase 1.1.1; decrease size
///   1.1.0: improve deposit and IncreaseLtv mechanic; mint wanS, wstkscUSD, wstkscETH
///   1.0.1: initVariants bugfix
/// @author Alien Deployer (https://github.com/a17)
contract SiloAdvancedLeverageStrategy is LeverageLendingBase, IFlashLoanRecipient {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.1.2";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function initialize(address[] memory addresses, uint[] memory nums, int24[] memory ticks) public initializer {
        if (addresses.length != 6 || nums.length != 1 || ticks.length != 0) {
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
        params.targetLeveragePercent = nums[0];
        __LeverageLendingBase_init(params);

        IERC20(params.collateralAsset).forceApprove(params.lendingVault, type(uint).max);
        IERC20(params.borrowAsset).forceApprove(params.borrowingVault, type(uint).max);
        address swapper = IPlatform(params.platform).swapper();
        IERC20(params.collateralAsset).forceApprove(swapper, type(uint).max);
        IERC20(params.borrowAsset).forceApprove(swapper, type(uint).max);

        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        // Multiplier of flash amount for borrow on deposit. Default is 90_00 == 90%.
        $.depositParam0 = 90_00;
        // Multiplier of debt diff
        $.increaseLtvParam0 = 100_80;
        // Multiplier of swap borrow asset to collateral in flash loan callback
        $.increaseLtvParam1 = 99_00;
        // Multiplier of collateral diff
        $.decreaseLtvParam0 = 101_00;
        // Swap price impact tolerance
        $.swapPriceImpactTolerance0 = 1_000;
        $.swapPriceImpactTolerance1 = 1_000;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CALLBACKS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    receive() external payable {}

    /// @inheritdoc IFlashLoanRecipient
    function receiveFlashLoan(
        address[] memory tokens,
        uint[] memory amounts,
        uint[] memory feeAmounts,
        bytes memory /*userData*/
    ) external {
        // Flash loan is performed upon deposit and withdrawal
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        SiloAdvancedLib.receiveFlashLoan(platform(), $, tokens[0], amounts[0], feeAmounts[0]);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function getUniversalParams() external view returns (uint[] memory params) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        params = new uint[](10);
        params[0] = $.depositParam0;
        params[1] = $.depositParam1;
        params[2] = $.withdrawParam0;
        params[3] = $.withdrawParam1;
        params[4] = $.increaseLtvParam0;
        params[5] = $.increaseLtvParam1;
        params[6] = $.decreaseLtvParam0;
        params[7] = $.decreaseLtvParam1;
        params[8] = $.swapPriceImpactTolerance0;
        params[9] = $.swapPriceImpactTolerance1;
    }

    /// @inheritdoc IStrategy
    function isHardWorkOnDepositAllowed() external pure returns (bool) {
        return true;
    }

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.SILO_ADVANCED_LEVERAGE;
    }

    /// @inheritdoc IStrategy
    function initVariants(address platform_)
        public
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        IFactory.StrategyAvailableInitParams memory params =
            IFactory(IPlatform(platform_).factory()).strategyAvailableInitParams(keccak256(bytes(strategyLogicId())));
        uint len = params.initAddresses.length / 4;
        variants = new string[](len);
        addresses = new address[](len * 4);
        nums = new uint[](len);
        ticks = new int24[](0);
        for (uint i; i < len; ++i) {
            address collateralAsset = IERC4626(params.initAddresses[i * 2]).asset();
            address borrowAsset = IERC4626(params.initAddresses[i * 2 + 1]).asset();
            variants[i] = _generateDescription(params.initAddresses[i * 2], collateralAsset, borrowAsset);
            addresses[i * 2] = params.initAddresses[i * 2];
            addresses[i * 2 + 1] = params.initAddresses[i * 2 + 1];
            addresses[i * 2 + 2] = params.initAddresses[i * 2 + 2];
            addresses[i * 2 + 3] = params.initAddresses[i * 2 + 3];
            nums[i] = params.initNums[i];
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
        (,, uint targetLeverage) = SiloAdvancedLib.getLtvData(lendingVault, $.targetLeveragePercent);
        return (
            string.concat(CommonLib.u2s(siloId), " ", borrowAssetSymbol, " ", _formatLeverageShort(targetLeverage)),
            false
        );
    }

    /// @inheritdoc ILeverageLendingStrategy
    function realTvl() public view returns (uint tvl, bool trusted) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        
        // Load storage variables into memory
        address collateralAsset = $.collateralAsset;
        address borrowAsset = $.borrowAsset;
        address lendingVault = $.lendingVault;
        address borrowingVault = $.borrowingVault;

        // Calculate total value using memory variables
        uint collateralBalance = StrategyLib.balance(collateralAsset);
        uint totalInVaults = SiloAdvancedLib.calcTotal(platform(), 
            ILeverageLendingStrategy.LeverageLendingAddresses({
                collateralAsset: collateralAsset,
                borrowAsset: borrowAsset,
                lendingVault: lendingVault,
                borrowingVault: borrowingVault
            })
        );

        tvl = collateralBalance + totalInVaults;
        trusted = true;
    }

    /// @inheritdoc ILeverageLendingStrategy
    function realSharePrice() public view returns (uint sharePrice, bool trusted) {
        // Get real TVL first
        uint _realTvl;
        (_realTvl, trusted) = realTvl();
        
        // Load vault address into memory
        address _vault = vault();
        uint totalSupply = IERC20(_vault).totalSupply();
        
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
        return SiloAdvancedLib.health(platform(), $);
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
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        return SiloAdvancedLib.rebalanceDebt(platform(), newLtv, $);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        assets_ = assets();
        amounts_ = new uint[](1);
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        amounts_[0] = SiloAdvancedLib.totalCollateral($.lendingVault);
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
        LeverageLendingAddresses memory v = LeverageLendingAddresses({
            collateralAsset: $.collateralAsset,
            borrowAsset: $.borrowAsset,
            lendingVault: $.lendingVault,
            borrowingVault: $.borrowingVault
        });
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();

        uint totalWas = $base.total;

        ISilo(v.lendingVault).accrueInterest();
        ISilo(v.borrowingVault).accrueInterest();

        uint totalNow = StrategyLib.balance(v.collateralAsset) + SiloAdvancedLib.calcTotal(platform(), v);
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
            (uint sharePrice,) = realSharePrice();
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
        $.tempAction = CurrentAction.Deposit;
        
        // Load all storage variables into memory first
        address collateralAsset = $.collateralAsset;
        address borrowAsset = $.borrowAsset;
        address lendingVault = $.lendingVault;
        address borrowingVault = $.borrowingVault;

        // Calculate initial value
        uint valueWas = _calculateTotalValue(collateralAsset, borrowAsset, lendingVault, borrowingVault);

        // Execute flash loan and get final value
        uint valueNow = _executeDepositFlashLoan(
            $,
            amounts[0],
            collateralAsset,
            borrowAsset,
            lendingVault,
            borrowingVault
        );

        // Calculate output value
        value = _calculateDepositValue(amounts[0], valueWas, valueNow);

        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        $base.total += value;
    }

    function _executeDepositFlashLoan(
        LeverageLendingBaseStorage storage $,
        uint amount,
        address collateralAsset,
        address borrowAsset,
        address lendingVault,
        address borrowingVault
    ) internal returns (uint) {
        // Get LTV data and prices
        (,, uint targetLeverage) = SiloAdvancedLib.getLtvData(lendingVault, $.targetLeveragePercent);
        (uint priceCtoB,) = SiloAdvancedLib.getPrices(platform(), lendingVault, borrowingVault);

        // Calculate flash loan amount
        uint initialCollateralValue = amount * priceCtoB / 1e18;
        uint flashAmount = initialCollateralValue * targetLeverage / INTERNAL_PRECISION;
        flashAmount = flashAmount * $.depositParam0 / INTERNAL_PRECISION;

        // Execute flash loan
        address[] memory flashAssets = new address[](1);
        flashAssets[0] = borrowAsset;
        uint[] memory flashAmounts = new uint[](1);
        flashAmounts[0] = flashAmount;
        IBVault($.flashLoanVault).flashLoan(address(this), flashAssets, flashAmounts, "");

        // Return final value
        return _calculateTotalValue(collateralAsset, borrowAsset, lendingVault, borrowingVault);
    }

    function _calculateDepositValue(
        uint amount,
        uint valueWas,
        uint valueNow
    ) internal pure returns (uint) {
        if (valueNow > valueWas) {
            return amount + (valueNow - valueWas);
        } else {
            return amount - (valueWas - valueNow);
        }
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        $.tempAction = CurrentAction.Withdraw;
        
        // Load all storage variables into memory first
        address collateralAsset = $.collateralAsset;
        address borrowAsset = $.borrowAsset;
        address lendingVault = $.lendingVault;
        address borrowingVault = $.borrowingVault;
        
        amountsOut = new uint[](1);

        // Calculate initial value
        uint valueWas = _calculateTotalValue(collateralAsset, borrowAsset, lendingVault, borrowingVault);

        // Get LTV data and prices
        (uint maxLtv, uint maxLeverage,) = SiloAdvancedLib.getLtvData(lendingVault, $.targetLeveragePercent);
        (uint priceCtoB,) = SiloAdvancedLib.getPrices(platform(), lendingVault, borrowingVault);

        // Execute flash loan
        _calculateAndExecuteFlashLoan(
            $,
            value,
            maxLtv,
            maxLeverage,
            priceCtoB,
            borrowAsset
        );

        // Calculate final value and output amount
        uint valueNow = _calculateTotalValue(collateralAsset, borrowAsset, lendingVault, borrowingVault);
        amountsOut[0] = _calculateOutputAmount(
            collateralAsset,
            value,
            valueWas,
            valueNow
        );

        if (receiver != address(this)) {
            IERC20(collateralAsset).safeTransfer(receiver, amountsOut[0]);
        }

        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        $base.total -= value;
    }

    function _calculateTotalValue(
        address collateralAsset,
        address borrowAsset,
        address lendingVault,
        address borrowingVault
    ) internal view returns (uint) {
        return StrategyLib.balance(collateralAsset) + SiloAdvancedLib.calcTotal(platform(), 
            ILeverageLendingStrategy.LeverageLendingAddresses({
                collateralAsset: collateralAsset,
                borrowAsset: borrowAsset,
                lendingVault: lendingVault,
                borrowingVault: borrowingVault
            })
        );
    }

    function _calculateAndExecuteFlashLoan(
        LeverageLendingBaseStorage storage $,
        uint value,
        uint maxLtv,
        uint maxLeverage,
        uint priceCtoB,
        address borrowAsset
    ) internal returns (uint) {
        uint collateralAmount = value * maxLeverage / INTERNAL_PRECISION;
        uint flashAmount = (collateralAmount * maxLtv / 1e18) * priceCtoB / 1e18;

        address[] memory flashAssets = new address[](1);
        flashAssets[0] = borrowAsset;
        uint[] memory flashAmounts = new uint[](1);
        flashAmounts[0] = flashAmount;

        IBVault($.flashLoanVault).flashLoan(address(this), flashAssets, flashAmounts, "");
        return flashAmount;
    }

    function _calculateOutputAmount(
        address collateralAsset,
        uint value,
        uint valueWas,
        uint valueNow
    ) internal view returns (uint) {
        uint bal = StrategyLib.balance(collateralAsset);
        uint valueDiff = valueWas > valueNow ? valueWas - valueNow : valueNow - valueWas;
        return Math.min(
            valueWas > valueNow ? value - valueDiff : value + valueDiff,
            bal
        );
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
