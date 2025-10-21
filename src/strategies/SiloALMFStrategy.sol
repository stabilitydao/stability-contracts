// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IControllable} from "../interfaces/IControllable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IFlashLoanRecipient} from "../integrations/balancer/IFlashLoanRecipient.sol";
import {ILeverageLendingStrategy} from "../interfaces/ILeverageLendingStrategy.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IMerklStrategy} from "../interfaces/IMerklStrategy.sol";
import {IFarmingStrategy} from "../interfaces/IFarmingStrategy.sol";
import {IUniswapV3FlashCallback} from "../integrations/uniswapv3/IUniswapV3FlashCallback.sol";
import {IAlgebraFlashCallback} from "../integrations/algebrav4/callback/IAlgebraFlashCallback.sol";
import {IBalancerV3FlashCallback} from "../integrations/balancerv3/IBalancerV3FlashCallback.sol";
import {LeverageLendingBase} from "./base/LeverageLendingBase.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StrategyBase} from "./base/StrategyBase.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {SiloALMFLib} from "./libs/SiloALMFLib.sol";
import {SiloALMFLib2} from "./libs/SiloALMFLib2.sol";
import {FarmMechanicsLib} from "./libs/FarmMechanicsLib.sol";
import {FarmingStrategyBase} from "./base/FarmingStrategyBase.sol";
import {MerklStrategyBase} from "./base/MerklStrategyBase.sol";

/// @title Silo V2 advanced leverage Merkl farm strategy
/// Changelog:
///   1.1.1: StrategyBase 2.5.1
///   1.1.0: Each write operation caches prices of MetaUSD - #348
///   1.0.1: Use new version of setLastBlockDefenseDisabledTx
///   1.0.0: Initial version - #330
/// @author dvpublic (https://github.com/dvpublic)
contract SiloALMFStrategy is
    LeverageLendingBase,
    FarmingStrategyBase,
    MerklStrategyBase,
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
    string public constant VERSION = "1.1.1";

    //region ----------------------------------- Initialization
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    /// @param addresses [platform, vault]
    /// @param nums [farmId]
    function initialize(address[] memory addresses, uint[] memory nums, int24[] memory ticks) public initializer {
        if (addresses.length != 2 || nums.length != 1 || ticks.length != 0) {
            revert IControllable.IncorrectInitParams();
        }
        IFactory.Farm memory farm = _getFarm(addresses[0], nums[0]);
        if (farm.addresses.length != 4 || farm.nums.length != 0 || farm.ticks.length != 0) {
            revert IFarmingStrategy.BadFarm();
        }

        // slither-disable-next-line unused-return
        LeverageLendingStrategyBaseInitParams memory params;

        params.platform = addresses[0];
        params.strategyId = StrategyIdLib.SILO_ALMF_FARM;
        params.vault = addresses[1];
        params.collateralAsset = IERC4626(farm.addresses[SiloALMFLib2.FARM_ADDRESS_LENDING_VAULT_INDEX]).asset();
        params.borrowAsset = IERC4626(farm.addresses[SiloALMFLib2.FARM_ADDRESS_BORROWING_VAULT_INDEX]).asset();
        params.lendingVault = farm.addresses[SiloALMFLib2.FARM_ADDRESS_LENDING_VAULT_INDEX];
        params.borrowingVault = farm.addresses[SiloALMFLib2.FARM_ADDRESS_BORROWING_VAULT_INDEX];
        params.flashLoanVault = farm.addresses[SiloALMFLib2.FARM_ADDRESS_FLASH_LOAN_VAULT_INDEX];
        params.helper = farm.addresses[SiloALMFLib2.FARM_ADDRESS_SILO_LENS_INDEX]; // SiloLens
        params.targetLeveragePercent = 85_00;

        __LeverageLendingBase_init(params); // __StrategyBase_init is called inside
        __FarmingStrategyBase_init(addresses[0], nums[0]);

        IERC20(params.collateralAsset).forceApprove(params.lendingVault, type(uint).max);
        IERC20(params.borrowAsset).forceApprove(params.borrowingVault, type(uint).max);

        address swapper = IPlatform(params.platform).swapper();
        IERC20(params.collateralAsset).forceApprove(swapper, type(uint).max);
        IERC20(params.borrowAsset).forceApprove(swapper, type(uint).max);

        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        // Multiplier of flash amount for borrow on deposit. Default is 100_00 = 100%
        $.depositParam0 = 100_00;
        // Multiplier of borrow amount to take into account max flash loan fee in maxDeposit. Default is 99_80 = 99.8%
        $.depositParam1 = 99_80;
        // Multiplier of debt diff
        $.increaseLtvParam0 = 100_80;
        // Multiplier of swap borrow asset to collateral in flash loan callback
        $.increaseLtvParam1 = 99_00;
        // Multiplier of collateral diff
        $.decreaseLtvParam0 = 101_00;

        // Swap price impact tolerance
        $.swapPriceImpactTolerance0 = 1_000;
        $.swapPriceImpactTolerance1 = 1_000;

        // Multiplier of flash amount for withdraw. Default is 100_00 == 100%.
        $.withdrawParam0 = 100_00;
        // Multiplier of amount allowed to be deposited after withdraw. Default is 100_00 == 100% (deposit forbidden)
        $.withdrawParam1 = 100_00;
        // withdrawParam2 allows to disable withdraw through increasing ltv if leverage is near to target
        $.withdrawParam2 = 100_00;
    }
    //endregion ----------------------------------- Initialization

    //region ----------------------------------- Callbacks
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CALLBACKS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    receive() external payable {}

    //endregion ----------------------------------- Callbacks

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
        SiloALMFLib.receiveFlashLoanBalancerV2(platform(), $, tokens, amounts, feeAmounts);
    }

    /// @inheritdoc IBalancerV3FlashCallback
    function receiveFlashLoanV3(
        address token,
        uint amount,
        bytes memory /*userData*/
    ) external {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        SiloALMFLib.receiveFlashLoanV3(platform(), $, token, amount);
    }

    /// @inheritdoc IUniswapV3FlashCallback
    function uniswapV3FlashCallback(uint fee0, uint fee1, bytes calldata userData) external {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        SiloALMFLib.uniswapV3FlashCallback(platform(), $, fee0, fee1, userData);
    }

    /// @inheritdoc IAlgebraFlashCallback
    function algebraFlashCallback(uint fee0, uint fee1, bytes calldata userData) external {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        SiloALMFLib.uniswapV3FlashCallback(platform(), $, fee0, fee1, userData);
    }

    //endregion ----------------------------------- Flash loan

    //region ----------------------------------- View
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function isHardWorkOnDepositAllowed() external pure returns (bool) {
        return false;
    }

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.SILO_ALMF_FARM;
    }

    /// @inheritdoc IStrategy
    function initVariants(address platform_)
        public
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        return SiloALMFLib2.initVariants(platform_);
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        return SiloALMFLib2._generateDescription($.lendingVault, $.collateralAsset, $.borrowAsset);
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external view override returns (string memory, bool) {
        return SiloALMFLib.getSpecificName(_getLeverageLendingBaseStorage());
    }

    /// @inheritdoc ILeverageLendingStrategy
    function realTvl() public view returns (uint tvl, bool trusted) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        return SiloALMFLib.realTvl(platform(), $);
    }

    function _realSharePrice() internal view override returns (uint sharePrice, bool trusted) {
        return SiloALMFLib._realSharePrice(platform(), _getLeverageLendingBaseStorage(), vault());
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
        return SiloALMFLib.health(platform(), $);
    }

    /// @inheritdoc ILeverageLendingStrategy
    function getSupplyAndBorrowAprs() external view returns (uint supplyApr, uint borrowApr) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        return SiloALMFLib._getDepositAndBorrowAprs($.helper, $.lendingVault, $.borrowingVault);
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(FarmingStrategyBase, LeverageLendingBase, MerklStrategyBase)
        returns (bool)
    {
        return interfaceId == type(IFarmingStrategy).interfaceId || interfaceId == type(IMerklStrategy).interfaceId
            || interfaceId == type(ILeverageLendingStrategy).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IStrategy
    function maxDepositAssets() public view override returns (uint[] memory amounts) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        return SiloALMFLib.maxDepositAssets($);
    }

    //endregion ----------------------------------- View

    //region ----------------------------------- Leverage lending base
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   LEVERAGE LENDING BASE                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _rebalanceDebt(uint newLtv) internal override returns (uint resultLtv) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();

        SiloALMFLib.prepareWriteOp(platform(), $.collateralAsset);
        resultLtv = SiloALMFLib.rebalanceDebt(platform(), newLtv, $);
        SiloALMFLib.unprepareWriteOp(platform(), $.collateralAsset);
    }

    //endregion ----------------------------------- Leverage lending base

    //region ----------------------------------- Strategy base
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        assets_ = assets();

        amounts_ = new uint[](1);
        amounts_[0] = SiloALMFLib.totalCollateral($.lendingVault);
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
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();

        SiloALMFLib.prepareWriteOp(platform(), $.collateralAsset);
        __assets = assets();
        (__amounts, __rewardAssets, __rewardAmounts) =
            SiloALMFLib._claimRevenue($, _getStrategyBaseStorage(), _getFarmingStrategyBaseStorage());
        SiloALMFLib.unprepareWriteOp(platform(), $.collateralAsset);
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
    function _depositAssets(
        uint[] memory amounts,
        bool /*claimRevenue*/
    ) internal override returns (uint value) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        address[] memory _assets = assets();

        SiloALMFLib.prepareWriteOp(platform(), $.collateralAsset);
        value = SiloALMFLib.depositAssets($, $base, amounts[0], _assets[0]);
        SiloALMFLib.unprepareWriteOp(platform(), $.collateralAsset);
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();

        SiloALMFLib.prepareWriteOp(platform(), $.collateralAsset);
        amountsOut = SiloALMFLib.withdrawAssets(platform(), $, $base, value, receiver);
        SiloALMFLib.unprepareWriteOp(platform(), $.collateralAsset);
    }

    /// @inheritdoc IStrategy
    function autoCompoundingByUnderlyingProtocol()
        public
        view
        virtual
        override(LeverageLendingBase, StrategyBase)
        returns (bool)
    {
        return true;
    }

    function _compound() internal override(LeverageLendingBase, StrategyBase) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();

        SiloALMFLib.prepareWriteOp(platform(), $.collateralAsset);
        SiloALMFLib._compound(platform(), vault(), $, _getStrategyBaseStorage());
        SiloALMFLib.unprepareWriteOp(platform(), $.collateralAsset);
    }

    //endregion ----------------------------------- Strategy base

    //region ----------------------------------- FarmingStrategy
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     FARMING STRATEGY                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc FarmingStrategyBase
    function _liquidateRewards(
        address exchangeAsset,
        address[] memory rewardAssets_,
        uint[] memory rewardAmounts_
    ) internal override(FarmingStrategyBase, StrategyBase, LeverageLendingBase) returns (uint earnedExchangeAsset) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();

        SiloALMFLib.prepareWriteOp(platform(), $.collateralAsset);
        earnedExchangeAsset = FarmingStrategyBase._liquidateRewards(exchangeAsset, rewardAssets_, rewardAmounts_);
        SiloALMFLib.unprepareWriteOp(platform(), $.collateralAsset);
    }

    /// @inheritdoc IFarmingStrategy
    function canFarm() external view override returns (bool) {
        IFactory.Farm memory farm = _getFarm();
        return farm.status == 0;
    }

    /// @inheritdoc IFarmingStrategy
    function farmMechanics() external pure returns (string memory) {
        return FarmMechanicsLib.MERKL;
    }

    //endregion ----------------------------------- FarmingStrategy
}
