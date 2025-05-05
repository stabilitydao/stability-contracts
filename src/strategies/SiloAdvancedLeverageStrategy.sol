// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../lib/forge-std/src/console.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {ConstantsLib} from "../core/libs/ConstantsLib.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IFlashLoanRecipient} from "../integrations/balancer/IFlashLoanRecipient.sol";
import {ILeverageLendingStrategy} from "../interfaces/ILeverageLendingStrategy.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";
import {ISiloConfig} from "../integrations/silo/ISiloConfig.sol";
import {ISiloLens} from "../integrations/silo/ISiloLens.sol";
import {ISilo} from "../integrations/silo/ISilo.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IVaultMainV3} from "../integrations/balancerv3/IVaultMainV3.sol";
import {IUniswapV3FlashCallback} from "../integrations/uniswapv3/IUniswapV3FlashCallback.sol";
import {IBalancerV3FlashCallback} from "../integrations/balancerv3/IBalancerV3FlashCallback.sol";
import {LeverageLendingBase} from "./base/LeverageLendingBase.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SiloAdvancedLib} from "./libs/SiloAdvancedLib.sol";
import {StrategyBase} from "./base/StrategyBase.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {StrategyLib} from "./libs/StrategyLib.sol";

/// @title Silo V2 advanced leverage strategy
/// Changelog:
///   1.1.2: realApr bugfix, emergency withdraw fix
///   1.1.1: use LeverageLendingBase 1.1.1; decrease size
///   1.1.0: improve deposit and IncreaseLtv mechanic; mint wanS, wstkscUSD, wstkscETH
///   1.0.1: initVariants bugfix
/// @author Alien Deployer (https://github.com/a17)
contract SiloAdvancedLeverageStrategy
is LeverageLendingBase,
IFlashLoanRecipient,
IUniswapV3FlashCallback,
IBalancerV3FlashCallback {
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
        $.withdrawParam0 = 100_00;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CALLBACKS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    receive() external payable {}

    //region ----------------------------------- Flash loan
    /// @inheritdoc IFlashLoanRecipient
    /// @dev Support of FLASH_LOAN_KIND_BALANCER_V2
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

    /// @notice This callback is called inside IVaultMainV3.unlock (balancer v3)
    /// @dev Support of FLASH_LOAN_KIND_BALANCER_V3
    /// @param token Token of flash loan
    /// @param amount Required amount of the flash loan
    function receiveFlashLoanV3(address token, uint amount, bytes memory /*userData*/) external {
        console.log("receiveFlashLoanV3.1", token, IERC20Metadata(token).symbol(), IERC20Metadata(token).decimals());
        // sender is vault, it's checked inside receiveFlashLoan
        IVaultMainV3 vault = IVaultMainV3(payable(msg.sender));

        // ensure that the vault has available amount
        require(IERC20(token).balanceOf(address(vault)) >= amount, IControllable.InsufficientBalance());

        console.log("receiveFlashLoanV3.2", amount, IERC20(token).balanceOf(address(vault)));
        // receive flash loan from the vault
        vault.sendTo(token, address(this), amount);

        console.log("receiveFlashLoanV3.3");
        // Flash loan is performed upon deposit and withdrawal
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        SiloAdvancedLib.receiveFlashLoan(platform(), $, token, amount, 0); // assume that flash loan is free, fee is 0

        console.log("receiveFlashLoanV3.4");
        // return flash loan back to the vault
        // assume that the amount was transferred back to the vault inside receiveFlashLoan()
        // we need only to register this transferring
        vault.settle(token, amount);
        console.log("receiveFlashLoanV3.5");
    }

    function uniswapV3FlashCallback(
        uint256 fee0,
        uint256 fee1,
        bytes calldata userData
    ) external {
        // sender is the pool, it's checked inside receiveFlashLoan
        (address token, uint amount, bool isToken0) = abi.decode(userData, (address, uint, bool));

        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        SiloAdvancedLib.receiveFlashLoan(platform(), $, token, amount, isToken0 ? fee0 : fee1);
    }
    //endregion ----------------------------------- Flash loan

    //region ----------------------------------- View
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

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
        return SiloAdvancedLib.realTvl(platform(), $);
    }

    function _realSharePrice() internal override view returns (uint sharePrice, bool trusted) {
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
        return SiloAdvancedLib.health(platform(), $);
    }

    /// @inheritdoc ILeverageLendingStrategy
    function getSupplyAndBorrowAprs() external view returns (uint supplyApr, uint borrowApr) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        return _getDepositAndBorrowAprs($.helper, $.lendingVault, $.borrowingVault);
    }

    //endregion ----------------------------------- View

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   LEVERAGE LENDING BASE                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _rebalanceDebt(uint newLtv) internal override returns (uint resultLtv) {
        console.log("!!!_rebalanceDebt", newLtv);
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        return SiloAdvancedLib.rebalanceDebt(platform(), newLtv, $);
    }

    //region ----------------------------------- Strategy base
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

        uint totalNow = StrategyLib.balance(v.collateralAsset) + SiloAdvancedLib.calcTotal(v);
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
        console.log("!!!_depositAssets", amounts[0]);
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        $.tempAction = CurrentAction.Deposit;
        LeverageLendingAddresses memory v = LeverageLendingAddresses({
            collateralAsset: $.collateralAsset,
            borrowAsset: $.borrowAsset,
            lendingVault: $.lendingVault,
            borrowingVault: $.borrowingVault
        });
        console.log("collateral balance", IERC20Metadata($.collateralAsset).balanceOf(address(this)));
        console.log("borrow balance", IERC20Metadata($.borrowAsset).balanceOf(address(this)));
        console.log("totalCollateral", SiloAdvancedLib.totalCollateral($.lendingVault));
        console.log("totalDebt", SiloAdvancedLib.totalDebt($.borrowingVault));
        console.log("borrow decimals", IERC20Metadata(v.borrowAsset).decimals());
        console.log("collateral decimals", IERC20Metadata(v.collateralAsset).decimals());

        console.log("collateralAsset", v.collateralAsset);
        console.log("borrowAsset", v.borrowAsset);
        console.log("lendingVault", v.lendingVault);
        console.log("borrowingVault", v.borrowingVault);
        console.log("flashLoanVault", $.flashLoanVault);
        console.log("flashLoanKind", $.flashLoanKind);
        address[] memory _assets = assets();
        uint valueWas = StrategyLib.balance(_assets[0]) + SiloAdvancedLib.calcTotal(v);
        console.log("_depositAssets.valueWas", valueWas);

        address[] memory flashAssets = new address[](1);
        flashAssets[0] = v.borrowAsset;
        uint[] memory flashAmounts = _getDepositFlashAmount($, v, amounts[0]);

        SiloAdvancedLib.requestFlashLoan($, flashAssets, flashAmounts);

        uint valueNow = StrategyLib.balance(_assets[0]) + SiloAdvancedLib.calcTotal(v);
        console.log("_depositAssets.valueNow", valueNow);

        if (valueNow > valueWas) {
            //console.log('deposit profit', valueNow - valueWas);
            value = amounts[0] + (valueNow - valueWas);
        } else {
            //console.log('deposit loss', valueWas - valueNow);
            value = amounts[0] - (valueWas - valueNow);
        }
        console.log("_depositAssets.balance-B", StrategyLib.balance(v.borrowAsset));
        console.log("_depositAssets.value (delta)", value);

        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        console.log("$base.total before", $base.total);
        $base.total += value;
        console.log("$base.total after", $base.total);
    }

    function _getDepositFlashAmount(
        LeverageLendingBaseStorage storage $,
        LeverageLendingAddresses memory v,
        uint amount
    ) internal view returns (uint[] memory flashAmounts) {
        (,, uint targetLeverage) = SiloAdvancedLib.getLtvData(v.lendingVault, $.targetLeveragePercent);
        console.log("_depositAssets.targetLeverage", targetLeverage);

        (uint priceCtoB, ) = SiloAdvancedLib.getPrices(v.lendingVault, v.borrowingVault);
        console.log("_depositAssets.priceCtoB", priceCtoB);

        flashAmounts = new uint[](1);
        flashAmounts[0] = amount
            * priceCtoB
            * (10**IERC20Metadata(v.borrowAsset).decimals())
            * (targetLeverage - INTERNAL_PRECISION) / INTERNAL_PRECISION
            / 1e18 // priceCtoB has decimals 1e18
            / (10**IERC20Metadata(v.collateralAsset).decimals());
        console.log("_depositAssets.flashAmounts[0]", flashAmounts[0]);
        // not sure that its right way, but its working
        // flashAmounts[0] = flashAmounts[0] * $.depositParam0 / INTERNAL_PRECISION;

        console.log("_depositAssets.depositParam0", $.depositParam0);
        console.log("_depositAssets.flashAmounts[0]", flashAmounts[0]);
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        console.log("!!!_withdrawAssets.value", value);
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        $.tempAction = CurrentAction.Withdraw;
        LeverageLendingAddresses memory v = LeverageLendingAddresses({
            collateralAsset: $.collateralAsset,
            borrowAsset: $.borrowAsset,
            lendingVault: $.lendingVault,
            borrowingVault: $.borrowingVault
        });
        amountsOut = new uint[](1);

        uint valueWas = StrategyLib.balance(v.collateralAsset) + SiloAdvancedLib.calcTotal(v);
        console.log("_withdrawAssets.valueWas", valueWas);

        (uint ltv,,,,,) = health();
        console.log("_withdrawAssets.ltv", ltv);

        (uint maxLtv, uint maxLeverage, uint targetLeverage) = SiloAdvancedLib.getLtvData(v.lendingVault, $.targetLeveragePercent);
        console.log("_withdrawAssets.maxLtv", maxLtv);
        console.log("_withdrawAssets.maxLeverage", maxLeverage);
        console.log("_withdrawAssets.targetLeverage", targetLeverage);

        (uint priceCtoB,) = SiloAdvancedLib.getPrices(v.lendingVault, v.borrowingVault);
        console.log("_withdrawAssets.priceCtoB", priceCtoB);

        {
            uint collateralAmountToWithdraw = value == $base.total // todo far from ideal..
                ? value * maxLeverage / INTERNAL_PRECISION
                : value * targetLeverage / INTERNAL_PRECISION;
            // uint collateralAmountToWithdraw = value * maxLeverage / INTERNAL_PRECISION;

            console.log("_withdrawAssets.collateralAmountToWithdraw", collateralAmountToWithdraw);
            uint withdrawParam0 = $.withdrawParam0;
            $.tempCollateralAmount = collateralAmountToWithdraw;
            uint[] memory flashAmounts = new uint[](1);
            flashAmounts[0] = collateralAmountToWithdraw * maxLtv / 1e18
                * priceCtoB
                * (withdrawParam0 == 0 ? INTERNAL_PRECISION : withdrawParam0)
                * (10**IERC20Metadata(v.borrowAsset).decimals())
                / 1e18 // priceCtoB has decimals 1e18
                / INTERNAL_PRECISION // withdrawParam0
                / (10**IERC20Metadata(v.collateralAsset).decimals());
            console.log("_withdrawAssets.flashAmounts[0]", flashAmounts[0]);
            address[] memory flashAssets = new address[](1);
            flashAssets[0] = $.borrowAsset;
            SiloAdvancedLib.requestFlashLoan($, flashAssets, flashAmounts);
        }

        uint valueNow = StrategyLib.balance(v.collateralAsset) + SiloAdvancedLib.calcTotal(v);
        console.log("_withdrawAssets.valueNow.C", valueNow);
        console.log("_withdrawAssets.balance-B", StrategyLib.balance(v.borrowAsset));

        uint bal = StrategyLib.balance(v.collateralAsset);
        console.log("_withdrawAssets.bal.C", bal);
        if (valueWas > valueNow) {
            //console.log('withdraw loss', valueWas - valueNow);
            amountsOut[0] = Math.min(value - (valueWas - valueNow), bal);
        } else {
            //console.log('withdraw profit', valueNow - valueWas);
            amountsOut[0] = Math.min(value + (valueNow - valueWas), bal);
        }
        console.log("_withdrawAssets.amountsOut[0]", amountsOut[0]);

        if (receiver != address(this)) {
            console.log("transfer C to user", amountsOut[0]);
            IERC20(v.collateralAsset).safeTransfer(receiver, amountsOut[0]);
        }

        console.log("$base.total.before", $base.total);
        $base.total -= value;
        console.log("$base.total.after", $base.total);
    }
    //endregion ----------------------------------- Strategy base

    //region ----------------------------------- Internal logic
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

    //endregion ----------------------------------- Internal logic
}
