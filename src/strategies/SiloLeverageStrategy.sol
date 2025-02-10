// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {StrategyBase} from "./base/StrategyBase.sol";
import {LeverageLendingBase} from "./base/LeverageLendingBase.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {StrategyLib} from "./libs/StrategyLib.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";
import {ILeverageLendingStrategy} from "../interfaces/ILeverageLendingStrategy.sol";
import {ISilo} from "../integrations/silo/ISilo.sol";
import {ISiloConfig} from "../integrations/silo/ISiloConfig.sol";
import {ISiloOracle} from "../integrations/silo/ISiloOracle.sol";
import {ISiloLens} from "../integrations/silo/ISiloLens.sol";
import {IFlashLoanRecipient} from "../integrations/balancer/IFlashLoanRecipient.sol";
import {IBVault} from "../integrations/balancer/IBVault.sol";

contract SiloLeverageStrategy is LeverageLendingBase, IFlashLoanRecipient {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

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
        address flashLoanVault = $.flashLoanVault;
        if (msg.sender != flashLoanVault) {
            revert IControllable.IncorrectMsgSender();
        }

        if ($.tempAction == CurrentAction.Deposit) {
            // tokens[0] is collateral asset
            uint tempBorrowAmount = $.tempBorrowAmount;

            // supply
            ISilo($.lendingVault).deposit(amounts[0], address(this), ISilo.CollateralType.Collateral);

            // borrow
            ISilo($.borrowingVault).borrow(tempBorrowAmount, address(this), address(this));

            // swap
            _swap($.borrowAsset, tokens[0], tempBorrowAmount);

            // pay flash loan
            IERC20(tokens[0]).safeTransfer(flashLoanVault, amounts[0] + feeAmounts[0]);

            // reset temp vars
            $.tempBorrowAmount = 0;
        }

        if ($.tempAction == CurrentAction.Withdraw) {
            // tokens[0] is borrow asset
            address lendingVault = $.lendingVault;
            address collateralAsset = $.collateralAsset;
            uint tempCollateralAmount = $.tempCollateralAmount;

            // repay debt
            ISilo($.borrowingVault).repay(amounts[0], address(this));

            // withdraw
            uint collateralAmountTotal = IERC4626(lendingVault).convertToAssets(StrategyLib.balance(lendingVault));
            collateralAmountTotal -= collateralAmountTotal / 1000;
            ISilo(lendingVault).withdraw(
                Math.min(tempCollateralAmount, collateralAmountTotal),
                address(this),
                address(this),
                ISilo.CollateralType.Collateral
            );

            // swap
            _swap(collateralAsset, tokens[0], Math.min(tempCollateralAmount, StrategyLib.balance(collateralAsset)));

            // pay flash loan
            IERC20(tokens[0]).safeTransfer(flashLoanVault, amounts[0] + feeAmounts[0]);

            // swap unnecessary borrow asset
            _swap(tokens[0], collateralAsset, StrategyLib.balance(tokens[0]));

            // reset temp vars
            $.tempCollateralAmount = 0;
        }

        $.tempAction = CurrentAction.None;
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
            variants[i] = _generateDescription(collateralAsset, borrowAsset);
            addresses[i * 2] = params.initAddresses[i * 2];
            addresses[i * 2 + 1] = params.initAddresses[i * 2 + 1];
            addresses[i * 2 + 2] = params.initAddresses[i * 2 + 2];
            addresses[i * 2 + 3] = params.initAddresses[i * 2 + 3];
        }
    }

    function getRevenue() external view returns (address[] memory assets_, uint[] memory amounts) {}

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        return _generateDescription($.collateralAsset, $.borrowAsset);
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external pure override returns (string memory, bool) {
        return ("", false);
    }

    /// @inheritdoc ILeverageLendingStrategy
    function realTvl() public view returns (uint tvl, bool trusted) {
        IPriceReader priceReader = IPriceReader(IPlatform(platform()).priceReader());
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        address lendingVault = $.lendingVault;
        address collateralAsset = $.collateralAsset;
        address borrowAsset = $.borrowAsset;
        uint collateralAmount = StrategyLib.balance(collateralAsset)
            + IERC4626(lendingVault).convertToAssets(StrategyLib.balance(lendingVault));
        (uint collateralPrice, bool CollateralPriceTrusted) = priceReader.getPrice(collateralAsset);
        uint collateralUsd = collateralAmount * collateralPrice / 10 ** IERC20Metadata(collateralAsset).decimals();
        uint borrowedAmount = ISilo($.borrowingVault).maxRepay(address(this));
        (uint borrowAssetPrice, bool borrowAssetPriceTrusted) = priceReader.getPrice(borrowAsset);
        uint borrowAssetUsd = borrowedAmount * borrowAssetPrice / 10 ** IERC20Metadata(borrowAsset).decimals();
        tvl = collateralUsd - borrowAssetUsd;
        trusted = CollateralPriceTrusted && borrowAssetPriceTrusted;
    }

    /// @inheritdoc ILeverageLendingStrategy
    function realSharePrice() external view returns (uint sharePrice, bool trusted) {
        uint _realTvl;
        (_realTvl, trusted) = realTvl();
        uint totalSupply = IERC20(vault()).totalSupply();
        if (totalSupply != 0) {
            sharePrice = _realTvl * 1e18 / totalSupply;
        }
    }

    function state()
        external
        view
        returns (uint ltv, uint leverage, uint collateralAmount, uint debtAmount, uint targetLeveragePercent)
    {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        address lendingVault = $.lendingVault;
        address collateralAsset = $.collateralAsset;

        ltv = ISiloLens($.helper).getLtv($.lendingVault, address(this));
        ltv = ltv * INTERNAL_PRECISION / 1e18;

        collateralAmount = StrategyLib.balance(collateralAsset)
            + IERC4626(lendingVault).convertToAssets(StrategyLib.balance(lendingVault));
        debtAmount = ISilo($.borrowingVault).maxRepay(address(this));

        IPriceReader priceReader = IPriceReader(IPlatform(platform()).priceReader());
        (uint _realTvl,) = realTvl();
        (uint collateralPrice,) = priceReader.getPrice(collateralAsset);
        uint collateralUsd = collateralAmount * collateralPrice / 10 ** IERC20Metadata(collateralAsset).decimals();
        leverage = collateralUsd * INTERNAL_PRECISION / _realTvl;

        targetLeveragePercent = $.targetLeveragePercent;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        assets_ = assets();
        amounts_ = new uint[](1);
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        IERC4626 lendingVault = IERC4626($.lendingVault);
        uint lendShares = lendingVault.balanceOf(address(this));
        amounts_[0] = lendingVault.convertToAssets(lendShares);
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

        uint totalNow = StrategyLib.balance(v.collateralAsset) + _calcTotal(v);
        if (totalNow > totalWas) {
            __amounts[0] = totalNow - totalWas;
        }
        $base.total = totalNow;
        //console.log('total was', totalWas);
        //console.log('total now', totalNow);
    }

    /// @inheritdoc StrategyBase
    function _compound() internal override {}

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
        LeverageLendingAddresses memory v = LeverageLendingAddresses({
            collateralAsset: $.collateralAsset,
            borrowAsset: $.borrowAsset,
            lendingVault: $.lendingVault,
            borrowingVault: $.borrowingVault
        });
        address[] memory _assets = assets();
        uint valueWas = StrategyLib.balance(_assets[0]) + _calcTotal(v);

        (uint maxLtv,, uint targetLeverage) = _getLtvData(v.lendingVault, $.targetLeveragePercent);

        uint[] memory flashAmounts = new uint[](1);
        flashAmounts[0] = amounts[0] * targetLeverage / INTERNAL_PRECISION;

        (uint priceCtoB,) = _getPrices(ISilo(v.lendingVault).config(), v.lendingVault, v.borrowingVault);
        $.tempBorrowAmount = (flashAmounts[0] * maxLtv / 1e18) * priceCtoB / 1e18 - 2;

        IBVault($.flashLoanVault).flashLoan(address(this), _assets, flashAmounts, "");

        uint valueNow = StrategyLib.balance(_assets[0]) + _calcTotal(v);

        if (valueNow > valueWas) {
            // deposit profit
            value = amounts[0] + (valueNow - valueWas);
        } else {
            // deposit loss
            value = amounts[0] - (valueWas - valueNow);
        }

        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        $base.total += value;
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        $.tempAction = CurrentAction.Withdraw;
        LeverageLendingAddresses memory v = LeverageLendingAddresses({
            collateralAsset: $.collateralAsset,
            borrowAsset: $.borrowAsset,
            lendingVault: $.lendingVault,
            borrowingVault: $.borrowingVault
        });
        amountsOut = new uint[](1);

        uint valueWas = StrategyLib.balance(v.collateralAsset) + _calcTotal(v);

        (uint maxLtv, uint maxLeverage,) = _getLtvData(v.lendingVault, $.targetLeveragePercent);

        (uint priceCtoB,) = _getPrices(ISilo(v.lendingVault).config(), v.lendingVault, $.borrowingVault);

        {
            uint collateralAmountToWithdraw = value * maxLeverage / INTERNAL_PRECISION;
            $.tempCollateralAmount = collateralAmountToWithdraw;
            uint[] memory flashAmounts = new uint[](1);
            flashAmounts[0] = (collateralAmountToWithdraw * maxLtv / 1e18) * priceCtoB / 1e18;
            address[] memory flashAssets = new address[](1);
            flashAssets[0] = $.borrowAsset;
            IBVault($.flashLoanVault).flashLoan(address(this), flashAssets, flashAmounts, "");
        }

        uint valueNow = StrategyLib.balance(v.collateralAsset) + _calcTotal(v);

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

    /// @inheritdoc StrategyBase
    function _processRevenue(
        address[] memory, /*assets_*/
        uint[] memory /*amountsRemaining*/
    ) internal pure override returns (bool needCompound) {
        needCompound = true;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _generateDescription(address collateralAsset, address borrowAsset) internal view returns (string memory) {
        return string.concat(
            "Supply ",
            IERC20Metadata(collateralAsset).symbol(),
            " and borrow ",
            IERC20Metadata(borrowAsset).symbol(),
            " on Silo V2 with leverage looping"
        );
    }

    /// @dev LTV data
    /// @return maxLtv Max LTV with 18 decimals
    /// @return maxLeverage Max leverage multiplier with 4 decimals
    /// @return targetLeverage Target leverage multiplier with 4 decimals
    function _getLtvData(
        address lendingVault,
        uint targetLeveragePercent
    ) internal view returns (uint maxLtv, uint maxLeverage, uint targetLeverage) {
        address configContract = ISilo(lendingVault).config();
        ISiloConfig.ConfigData memory config = ISiloConfig(configContract).getConfig(lendingVault);
        maxLtv = config.maxLtv;
        maxLeverage = 1e18 * INTERNAL_PRECISION / (1e18 - maxLtv);
        targetLeverage = maxLeverage * targetLeveragePercent / INTERNAL_PRECISION;
    }

    function _getPrices(
        address configContract,
        address lendVault,
        address debtVault
    ) internal view returns (uint priceCtoB, uint priceBtoC) {
        ISiloConfig.ConfigData memory collateralConfig = ISiloConfig(configContract).getConfig(lendVault);
        address collateralOracle = collateralConfig.solvencyOracle;
        ISiloConfig.ConfigData memory borrowConfig = ISiloConfig(configContract).getConfig(debtVault);
        address borrowOracle = borrowConfig.solvencyOracle;

        //console.log('collateralOracle', collateralOracle);
        //console.log('borrowOracle', borrowOracle);
        //console.log('collateral token', collateralConfig.token);

        if (collateralOracle != address(0) && borrowOracle == address(0)) {
            priceCtoB = ISiloOracle(collateralOracle).quote(
                10 ** IERC20Metadata(collateralConfig.token).decimals(), collateralConfig.token
            );
            priceBtoC = 1e18 * 1e18 / priceCtoB;
        } else if (collateralOracle == address(0) && borrowOracle != address(0)) {
            priceBtoC =
                ISiloOracle(borrowOracle).quote(10 ** IERC20Metadata(borrowConfig.token).decimals(), borrowConfig.token);
            priceCtoB = 1e18 * 1e18 / priceBtoC;
        } else {
            revert("Not implemented yet");
        }

        //console.log('priceCtoB', priceCtoB);
        //console.log('priceBtoC', priceBtoC);
    }

    function _calcTotal(LeverageLendingAddresses memory v) internal view returns (uint) {
        uint collateralAmount = IERC4626(v.lendingVault).convertToAssets(StrategyLib.balance(v.lendingVault));
        uint borrowedAmount = ISilo(v.borrowingVault).maxRepay(address(this));
        //console.log('collateralAmount', collateralAmount);
        //console.log('borrowedAmount', borrowedAmount);
        (, uint priceBtoC) = _getPrices(ISilo(v.lendingVault).config(), v.lendingVault, v.borrowingVault);
        uint borrowedAmountPricedInCollateral = borrowedAmount * priceBtoC / 1e18;
        //console.log("Total", collateralAmount - borrowedAmountPricedInCollateral);
        return collateralAmount - borrowedAmountPricedInCollateral;
    }

    function _swap(address tokenIn, address tokenOut, uint amount) internal returns (uint amountOut) {
        uint outBalanceBefore = StrategyLib.balance(tokenOut);
        ISwapper swapper = ISwapper(IPlatform(platform()).swapper());
        swapper.swap(tokenIn, tokenOut, amount, 1000);
        amountOut = StrategyLib.balance(tokenOut) - outBalanceBefore;
    }
}
