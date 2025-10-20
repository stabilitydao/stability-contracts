// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
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
import {IVaultMainV3} from "../integrations/balancerv3/IVaultMainV3.sol";
import {IFlashLoanRecipient} from "../integrations/balancer/IFlashLoanRecipient.sol";
import {IUniswapV3FlashCallback} from "../integrations/uniswapv3/IUniswapV3FlashCallback.sol";
import {IBalancerV3FlashCallback} from "../integrations/balancerv3/IBalancerV3FlashCallback.sol";
import {IAlgebraFlashCallback} from "../integrations/algebrav4/callback/IAlgebraFlashCallback.sol";

/// @title Silo V2 leverage strategy
/// Changelog:
///   2.1.9: StrategyBase 2.6.5
///   2.1.8: StrategyBase 2.6.4
///   2.1.7: StrategyBase 2.6.3
///   2.1.6: StrategyBase 2.6.2
///   2.1.5: StrategyBase 2.6.1
///   2.1.4: StrategyBase 2.6.0
///   2.1.3: StrategyBase 2.5.1
///   2.1.2: Add maxDeploy, use StrategyBase 2.5.0 - #330
///   2.1.1: Use StrategyBase 2.4.0 - add default poolTvl, maxWithdrawAssets
///   2.1.0: Use StrategyBase 2.3.0 - add fuseMode
///   2.0.0:
///     * feat: use BeetsV3 OR UniswapV3-like DeX free flash loans #257, use universalAddress1 as flashLoanVault for borrow asset
///     * Change logic of withdraw: add deposit at the end and possibility to withdraw through increasing LTV
///     * use LeverageLendingBase 1.2.2
///   1.1.3: Move depositAssets impl to SiloLib to reduce size, use LeverageLendingBase 1.1.2, #269
///   1.1.2: realApr bugfix
///   1.1.1: use LeverageLendingBase 1.1.1
///   1.1.0: use LeverageLendingBase 1.1.0
/// @author Alien Deployer (https://github.com/a17)
/// @author dvpublic (https://github.com/dvpublic)
contract SiloLeverageStrategy is
    LeverageLendingBase,
    IFlashLoanRecipient,
    IUniswapV3FlashCallback,
    IBalancerV3FlashCallback,
    IAlgebraFlashCallback
{
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "2.1.9";

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

    //region ---------------- Callbacks (flash loan)
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

    /// @inheritdoc IBalancerV3FlashCallback
    function receiveFlashLoanV3(address token, uint amount, bytes memory /*userData*/ ) external {
        // sender is vault, it's checked inside receiveFlashLoan
        // we can use msg.sender below but $.flashLoanVault looks more safe
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        IVaultMainV3 vault = IVaultMainV3(payable($.flashLoanVault));

        // ensure that the vault has available amount
        require(IERC20(token).balanceOf(address(vault)) >= amount, IControllable.InsufficientBalance());

        // receive flash loan from the vault
        vault.sendTo(token, address(this), amount);

        // Flash loan is performed upon deposit and withdrawal
        SiloLib.receiveFlashLoan(platform(), $, token, amount, 0); // assume that flash loan is free, fee is 0

        // return flash loan back to the vault
        // assume that the amount was transferred back to the vault inside receiveFlashLoan()
        // we need only to register this transferring
        vault.settle(token, amount);
    }

    /// @inheritdoc IUniswapV3FlashCallback
    function uniswapV3FlashCallback(uint fee0, uint fee1, bytes calldata userData) external {
        // sender is the pool, it's checked inside receiveFlashLoan
        _uniswapV3FlashCallback(fee0, fee1, userData);
    }

    function algebraFlashCallback(uint fee0, uint fee1, bytes calldata userData) external {
        // sender is the pool, it's checked inside receiveFlashLoan
        _uniswapV3FlashCallback(fee0, fee1, userData);
    }

    //endregion ---------------- Callbacks (flash loan)

    //region ---------------- View
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
    //endregion ---------------- View

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   LEVERAGE LENDING BASE                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _rebalanceDebt(uint newLtv) internal override returns (uint resultLtv) {
        return SiloLib.rebalanceDebt(platform(), newLtv, _getLeverageLendingBaseStorage());
    }

    //region ---------------- Strategy base
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
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        return SiloLib.withdrawAssets(platform(), $, $base, value, receiver);
    }
    //endregion ---------------- Strategy base

    //region ---------------- Internal logic
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

    function _uniswapV3FlashCallback(uint fee0, uint fee1, bytes calldata userData) internal {
        // sender is the pool, it's checked inside receiveFlashLoan
        (address token, uint amount, bool isToken0) = abi.decode(userData, (address, uint, bool));

        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        SiloLib.receiveFlashLoan(platform(), $, token, amount, isToken0 ? fee0 : fee1);
    }

    //endregion ---------------- Internal logic
}
