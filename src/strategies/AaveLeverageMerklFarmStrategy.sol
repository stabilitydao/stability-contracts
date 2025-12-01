// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ALMFLib} from "./libs/ALMFLib.sol";
import {ALMFLib2} from "./libs/ALMFLib2.sol";
import {FarmMechanicsLib} from "./libs/FarmMechanicsLib.sol";
import {FarmingStrategyBase} from "./base/FarmingStrategyBase.sol";
import {IAToken} from "../integrations/aave/IAToken.sol";
import {IAlgebraFlashCallback} from "../integrations/algebrav4/callback/IAlgebraFlashCallback.sol";
import {IBalancerV3FlashCallback} from "../integrations/balancerv3/IBalancerV3FlashCallback.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IFarmingStrategy} from "../interfaces/IFarmingStrategy.sol";
import {IFlashLoanRecipient} from "../integrations/balancer/IFlashLoanRecipient.sol";
import {IMerklStrategy} from "../interfaces/IMerklStrategy.sol";
import {ILeverageLendingStrategy} from "../interfaces/ILeverageLendingStrategy.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IUniswapV3FlashCallback} from "../integrations/uniswapv3/IUniswapV3FlashCallback.sol";
import {LeverageLendingBase} from "./base/LeverageLendingBase.sol";
import {MerklStrategyBase} from "./base/MerklStrategyBase.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StrategyBase} from "./base/StrategyBase.sol";
import {VaultTypeLib} from "../core/libs/VaultTypeLib.sol";

/// @title Earns APR by lending assets on AAVE with leverage
/// @dev ALMF strategy
/// Changelog:
///   1.1.1: share price is calculated in collateral asset, not in usd
///   1.1.0: add support of e-mode
/// @author omriss (https://github.com/omriss)
contract AaveLeverageMerklFarmStrategy is
    FarmingStrategyBase,
    MerklStrategyBase,
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
    string public constant VERSION = "1.1.1";

    //region ----------------------------------- Initialization and restricted actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function initialize(address[] memory addresses, uint[] memory nums, int24[] memory ticks) public initializer {
        if (addresses.length != 2 || nums.length != 1 || ticks.length != 0) {
            revert IControllable.IncorrectInitParams();
        }
        IFactory.Farm memory farm = _getFarm(addresses[0], nums[0]);
        if (farm.addresses.length != 3 || farm.nums.length != 4 || farm.ticks.length != 0) {
            revert IFarmingStrategy.BadFarm();
        }

        // slither-disable-next-line uninitialized-local
        LeverageLendingStrategyBaseInitParams memory params;

        params.platform = addresses[0];
        params.strategyId = ALMFLib2.STRATEGY_LOGIC_ID;
        params.vault = addresses[1];
        params.collateralAsset =
            IAToken(farm.addresses[ALMFLib.FARM_ADDRESS_LENDING_VAULT_INDEX]).UNDERLYING_ASSET_ADDRESS();
        params.borrowAsset =
            IAToken(farm.addresses[ALMFLib.FARM_ADDRESS_BORROWING_VAULT_INDEX]).UNDERLYING_ASSET_ADDRESS();
        params.lendingVault = farm.addresses[ALMFLib.FARM_ADDRESS_LENDING_VAULT_INDEX];
        params.borrowingVault = farm.addresses[ALMFLib.FARM_ADDRESS_BORROWING_VAULT_INDEX];
        params.flashLoanVault = farm.addresses[ALMFLib.FARM_ADDRESS_FLASH_LOAN_VAULT_INDEX];
        // params.helper = address(0); // not used
        // params.targetLeveragePercent = 0; // not used

        __LeverageLendingBase_init(params); // __StrategyBase_init is called inside
        __FarmingStrategyBase_init(addresses[0], nums[0]);

        // set up params and approves, switch to e-mode
        ALMFLib2._postInit(
            _getLeverageLendingBaseStorage(),
            params.platform,
            params.lendingVault,
            params.collateralAsset,
            params.borrowAsset,
            farm
        );
    }

    //endregion ----------------------------------- Initialization and restricted actions

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
        ALMFLib.receiveFlashLoanBalancerV2(platform(), $, tokens, amounts, feeAmounts);
    }

    /// @inheritdoc IBalancerV3FlashCallback
    function receiveFlashLoanV3(
        address token,
        uint amount,
        bytes memory /*userData*/
    ) external {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        ALMFLib.receiveFlashLoanV3(platform(), $, token, amount);
    }

    /// @inheritdoc IUniswapV3FlashCallback
    function uniswapV3FlashCallback(uint fee0, uint fee1, bytes calldata userData) external {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        ALMFLib.uniswapV3FlashCallback(platform(), $, fee0, fee1, userData);
    }

    /// @inheritdoc IAlgebraFlashCallback
    function algebraFlashCallback(uint fee0, uint fee1, bytes calldata userData) external {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        ALMFLib.uniswapV3FlashCallback(platform(), $, fee0, fee1, userData);
    }

    //endregion ----------------------------------- Flash loan

    //region ----------------------------------- View functions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function isHardWorkOnDepositAllowed() external pure returns (bool) {
        return false;
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
    function strategyLogicId() public pure override returns (string memory) {
        return ALMFLib2.STRATEGY_LOGIC_ID;
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        return ALMFLib2.genDesc(_getFarm());
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external view override returns (string memory name, bool showInVaultSymbol) {
        (name, showInVaultSymbol) = ALMFLib2.getSpecificName(_getLeverageLendingBaseStorage(), _getFarm());
    }

    /// @inheritdoc IStrategy
    function supportedVaultTypes()
        external
        pure
        override(LeverageLendingBase, StrategyBase)
        returns (string[] memory types)
    {
        types = new string[](1);
        types[0] = VaultTypeLib.COMPOUNDING;
    }

    /// @inheritdoc IStrategy
    function initVariants(address platform_)
        external
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        (variants, addresses, nums, ticks) = ALMFLib2.initVariants(platform_);
    }

    /// @inheritdoc IStrategy
    function total() public view override returns (uint) {
        return ALMFLib.total(_getLeverageLendingBaseStorage());
    }

    /// @inheritdoc IStrategy
    function getRevenue()
        public
        view
        override(IStrategy, LeverageLendingBase)
        returns (address[] memory assets_, uint[] memory amounts)
    {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        ALMFLib.AlmfStrategyStorage storage $a = ALMFLib._getStorage();
        (assets_, amounts) = ALMFLib.getRevenue($, $a.lastSharePrice, vault());
    }

    /// @inheritdoc IStrategy
    function isReadyForHardWork() external pure override(IStrategy, LeverageLendingBase) returns (bool isReady) {
        isReady = true;
    }

    /// @inheritdoc IStrategy
    function poolTvl() public view override returns (uint tvlUsd) {
        return ALMFLib2._poolTvl(platform(), _getAToken());
    }

    /// @inheritdoc IStrategy
    /// @dev Assume that all amount can be withdrawn always for simplicity. Implement later.
    function maxWithdrawAssets(
        uint /*mode*/
    ) public pure override returns (uint[] memory amounts) {
        // for simplicity of v.1.0: any amount can be withdrawn
        return amounts;
    }

    /// @inheritdoc IStrategy
    /// @dev Assume that any amount can be deposit always for simplicity. Implement later.
    function maxDepositAssets() public pure override returns (uint[] memory amounts) {
        // in real implementation we should take into account both borrow and supply cap
        // result amount should take leverage into account
        // max deposit is limited by amount available to borrow from the borrow pool

        // for simplicity of v1.0: any amount can be deposited
        return amounts;
    }

    /// @notice Get prices of collateral and borrow assets from Aave price oracle in USD, decimals 18
    /// @return collateralPrice Price of collateral asset ($/collateral asset, decimals 18)
    /// @return borrowPrice Price of borrow asset ($/borrow asset, decimals 18)
    function getPrices() public view returns (uint collateralPrice, uint borrowPrice) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        (collateralPrice, borrowPrice) = ALMFLib.getPrices($);
    }

    //endregion ----------------------------------- View functions

    //region ----------------------------------- Additional functionality
    /// @notice Get current threshold for the asset
    function threshold(address asset_) external view returns (uint) {
        return ALMFLib._getStorage().thresholds[asset_];
    }

    /// @notice Set threshold for the asset
    function setThreshold(address asset_, uint threshold_) external onlyOperator {
        ALMFLib.setThreshold(asset_, threshold_);
    }

    //endregion ----------------------------------- Additional functionality

    //region ----------------------------------- ILeverageLendingStrategy
    /// @inheritdoc ILeverageLendingStrategy
    function realTvl() public view returns (uint tvl, bool trusted) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        (tvl, trusted) = ALMFLib.realTvl($);
    }

    function _realSharePrice() internal view override returns (uint sharePrice, bool trusted) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        (sharePrice, trusted) = ALMFLib._realSharePrice($, vault());
    }

    /// @inheritdoc ILeverageLendingStrategy
    function health()
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
        (ltv, maxLtv, leverage, collateralAmount, debtAmount, targetLeveragePercent) =
            ALMFLib.health(platform(), _getLeverageLendingBaseStorage(), _getFarm());
    }

    /// @inheritdoc ILeverageLendingStrategy
    function getSupplyAndBorrowAprs() external view returns (uint supplyApr, uint borrowApr) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        (supplyApr, borrowApr) = ALMFLib._getDepositAndBorrowAprs($.lendingVault, $.collateralAsset, $.borrowAsset);
    }

    function _rebalanceDebt(uint newLtv) internal override returns (uint resultLtv) {
        return ALMFLib.rebalanceDebt(platform(), newLtv, _getLeverageLendingBaseStorage(), _getFarm());
    }

    //endregion ----------------------------------- ILeverageLendingStrategy

    //region ----------------------------------- Strategy base
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        assets_ = $base._assets;
        amounts_ = new uint[](1);
        amounts_[0] = ALMFLib.totalCollateral($.lendingVault);
    }

    /// @inheritdoc StrategyBase
    //slither-disable-next-line unused-return
    function _depositAssets(uint[] memory amounts, bool) internal override returns (uint value) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();

        value = ALMFLib.depositAssets(platform(), $, _getFarm(), amounts[0]);
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();

        amountsOut = ALMFLib.withdrawAssets(platform(), $, _getFarm(), value, receiver);
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
        ALMFLib.AlmfStrategyStorage storage $a = ALMFLib._getStorage();
        FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();

        (__assets, __amounts, __rewardAssets, __rewardAmounts) = ALMFLib.claimRevenue($, $a, $f, $base, vault());
    }

    /// @inheritdoc StrategyBase
    function _compound() internal override(LeverageLendingBase, StrategyBase) {
        address _platform = platform();
        return ALMFLib.compound(
            _platform, _getLeverageLendingBaseStorage(), _getStrategyBaseStorage(), _getFarm(_platform, farmId())
        );
    }

    /// @inheritdoc StrategyBase
    function _depositUnderlying(
        uint /*amount*/
    )
        internal
        pure
        override
        returns (
            uint[] memory /*amountsConsumed*/
        )
    {
        revert("no underlying");
    }

    /// @inheritdoc StrategyBase
    function _withdrawUnderlying(
        uint,
        /*amount*/
        address /*receiver*/
    ) internal pure override {
        revert("no underlying");
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

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax)
        internal
        view
        override
        returns (uint[] memory amountsConsumed, uint value)
    {
        (amountsConsumed, value) = ALMFLib.previewDepositValue(_getLeverageLendingBaseStorage(), amountsMax);
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
        return ALMFLib.liquidateRewards(
            platform(), exchangeAsset, rewardAssets_, rewardAmounts_, customPriceImpactTolerance()
        );
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

    //region ----------------------------------- Internal logic
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getAToken() internal view returns (address) {
        FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();
        return _getFarm(platform(), $f.farmId).addresses[0];
    }

    //endregion ----------------------------------- Internal logic
}
