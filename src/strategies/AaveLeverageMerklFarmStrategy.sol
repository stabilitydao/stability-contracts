// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ALMFLib} from "./libs/ALMFLib.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {FarmMechanicsLib} from "./libs/FarmMechanicsLib.sol";
import {FarmingStrategyBase} from "./base/FarmingStrategyBase.sol";
import {IAToken} from "../integrations/aave/IAToken.sol";
import {IAaveAddressProvider} from "../integrations/aave/IAaveAddressProvider.sol";
import {IAaveDataProvider} from "../integrations/aave/IAaveDataProvider.sol";
import {IAlgebraFlashCallback} from "../integrations/algebrav4/callback/IAlgebraFlashCallback.sol";
import {IBalancerV3FlashCallback} from "../integrations/balancerv3/IBalancerV3FlashCallback.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IFarmingStrategy} from "../interfaces/IFarmingStrategy.sol";
import {IFlashLoanRecipient} from "../integrations/balancer/IFlashLoanRecipient.sol";
import {IMerklStrategy} from "../interfaces/IMerklStrategy.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IPool} from "../integrations/aave/IPool.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IUniswapV3FlashCallback} from "../integrations/uniswapv3/IUniswapV3FlashCallback.sol";
import {IVaultMainV3} from "../integrations/balancerv3/IVaultMainV3.sol";
import {LeverageLendingBase} from "./base/LeverageLendingBase.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MerklStrategyBase} from "./base/MerklStrategyBase.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SharedLib} from "./libs/SharedLib.sol";
import {StrategyBase} from "./base/StrategyBase.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {StrategyLib} from "./libs/StrategyLib.sol";
import {VaultTypeLib} from "../core/libs/VaultTypeLib.sol";

/// @title Earns APR by lending assets on AAVE with leverage
/// @dev ALMF strategy
/// Changelog:
///   1.0.0: initial release
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
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.AaveLeverageMerklFarmStrategy")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant AAVE_MERKL_FARM_STRATEGY_STORAGE_LOCATION = 0; // todo


    string private constant STRATEGY_LOGIC_ID = StrategyIdLib.AAVE_LEVERAGE_MERKL_FARM;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.AaveLeverageMerklFarmStrategy
    struct AlmfStrategyStorage {
        uint lastSharePrice;
    }

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
        if (farm.addresses.length != 4 || farm.nums.length != 0 || farm.ticks.length != 0) {
            revert IFarmingStrategy.BadFarm();
        }

        // slither-disable-next-line unused-return
        LeverageLendingStrategyBaseInitParams memory params;

        params.platform = addresses[0];
        params.strategyId = STRATEGY_LOGIC_ID;
        params.vault = addresses[1];
        params.collateralAsset = IAToken(farm.addresses[ALMFLib.FARM_ADDRESS_LENDING_VAULT_INDEX]).UNDERLYING_ASSET_ADDRESS();
        params.borrowAsset = IAToken(farm.addresses[ALMFLib.FARM_ADDRESS_BORROWING_VAULT_INDEX]).UNDERLYING_ASSET_ADDRESS();
        params.lendingVault = farm.addresses[ALMFLib.FARM_ADDRESS_LENDING_VAULT_INDEX];
        params.borrowingVault = farm.addresses[ALMFLib.FARM_ADDRESS_BORROWING_VAULT_INDEX];
        params.flashLoanVault = farm.addresses[ALMFLib.FARM_ADDRESS_FLASH_LOAN_VAULT_INDEX];
        params.helper = address(0); // todo
        params.targetLeveragePercent = 85_00; // todo targetMinLtv and targetMaxLtv (from nums)

        __LeverageLendingBase_init(params); // __StrategyBase_init is called inside
        __FarmingStrategyBase_init(addresses[0], nums[0]);

        IERC20(params.collateralAsset).forceApprove(params.lendingVault, type(uint).max);
        IERC20(params.borrowAsset).forceApprove(params.borrowingVault, type(uint).max);

        address swapper = IPlatform(params.platform).swapper();
        IERC20(params.collateralAsset).forceApprove(swapper, type(uint).max);
        IERC20(params.borrowAsset).forceApprove(swapper, type(uint).max);

        // todo
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
        return STRATEGY_LOGIC_ID;
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        return _generateDescription(_getAToken());
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        //slither-disable-next-line too-many-digits
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x00d395), bytes3(0x000000)));
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external view override returns (string memory, bool) {
        address atoken = _getAToken();
        string memory shortAddr = SharedLib.shortAddress(IAToken(atoken).POOL());
        return (string.concat(IERC20Metadata(atoken).symbol(), " ", shortAddr), true);
    }

    /// @inheritdoc IStrategy
    function supportedVaultTypes() external pure override returns (string[] memory types) {
        types = new string[](1);
        types[0] = VaultTypeLib.COMPOUNDING;
    }

    /// @inheritdoc IStrategy
    function initVariants(address platform_)
    external
    view
    returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        addresses = new address[](0);
        ticks = new int24[](0);
        IFactory.Farm[] memory farms = IFactory(IPlatform(platform_).factory()).farms();
        uint len = farms.length;
        //slither-disable-next-line uninitialized-local
        uint _total;
        for (uint i; i < len; ++i) {
            IFactory.Farm memory farm = farms[i];
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, StrategyIdLib.AAVE_MERKL_FARM)) {
                ++_total;
            }
        }
        variants = new string[](_total);
        nums = new uint[](_total);
        _total = 0;
        for (uint i; i < len; ++i) {
            IFactory.Farm memory farm = farms[i];
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, StrategyIdLib.AAVE_MERKL_FARM)) {
                nums[_total] = i;
                variants[_total] = _generateDescription(farm.addresses[0]);
                ++_total;
            }
        }
    }

    /// @inheritdoc IStrategy
    function isHardWorkOnDepositAllowed() external pure returns (bool) {
        return false;
    }

    /// @inheritdoc IStrategy
    function total() public view override returns (uint) {
        return StrategyLib.balance(_getAToken());
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() external pure override returns (uint[] memory proportions) {
        proportions = new uint[](1);
        proportions[0] = 1e18;
    }

    /// @inheritdoc IStrategy
    function getRevenue() public view override returns (address[] memory assets_, uint[] memory amounts) {
        address aToken = _getAToken();
        uint newPrice = _getSharePrice(aToken);
        (assets_, amounts) = _getRevenue(newPrice, aToken);
    }

    /// @inheritdoc IStrategy
    function isReadyForHardWork() external pure override returns (bool isReady) {
        isReady = true;
    }

    /// @inheritdoc IStrategy
    function poolTvl() public view override returns (uint tvlUsd) {
        address aToken = _getAToken();
        address asset = IAToken(aToken).UNDERLYING_ASSET_ADDRESS();

        IPriceReader priceReader = IPriceReader(IPlatform(platform()).priceReader());

        // get price of 1 amount of asset in USD with decimals 18
        // assume that {trusted} value doesn't matter here
        // slither-disable-next-line unused-return
        (uint price,) = priceReader.getPrice(asset);

        return IAToken(aToken).totalSupply() * price / (10 ** IERC20Metadata(asset).decimals());
    }

    /// @inheritdoc IStrategy
    function maxWithdrawAssets(uint mode) public view override returns (uint[] memory amounts) {
        address aToken = _getAToken();
        address asset = IAToken(aToken).UNDERLYING_ASSET_ADDRESS();

        // currently available reserves in the pool
        uint availableLiquidity = IERC20(asset).balanceOf(aToken);

        // aToken balance of the strategy
        uint aTokenBalance = IERC20(aToken).balanceOf(address(this));

        amounts = new uint[](1);
        amounts[0] = mode == 0 ? Math.min(availableLiquidity, aTokenBalance) : aTokenBalance;

        // todo take leverage into account
    }

    /// @inheritdoc StrategyBase
    function _previewDepositUnderlying(uint amount) internal pure override returns (uint[] memory amountsConsumed) {
        amountsConsumed = new uint[](1);
        amountsConsumed[0] = amount;
    }

    /// @inheritdoc IStrategy
    function maxDepositAssets() public view override returns (uint[] memory amounts) {
        amounts = new uint[](1);

        address aToken = _getAToken();
        address asset = IAToken(aToken).UNDERLYING_ASSET_ADDRESS();

        // get supply cap for the borrow asset
        // slither-disable-next-line unused-return
        (, uint supplyCap) = IAaveDataProvider(
            IAaveAddressProvider(IPool(IAToken(aToken).POOL()).ADDRESSES_PROVIDER()).getPoolDataProvider()
        ).getReserveCaps(asset);

        if (supplyCap == 0) {
            amounts[0] = type(uint).max; // max deposit is not limited
        } else {
            supplyCap *= 10 ** IERC20Metadata(asset).decimals();

            // get total supplied amount for the borrow asset
            uint totalSupplied = IAToken(aToken).totalSupply();

            // calculate available amount to supply as (supply cap - total supplied)
            amounts[0] = (supplyCap > totalSupplied ? supplyCap - totalSupplied : 0) * 99 / 100; // leave 1% margin
            // todo result amount should take leverage into account

            // todo max deposit is limited by amount available to borrow from the borrow pool

        }
    }

//endregion ----------------------------------- View functions

//region ----------------------------------- ILeverageLendingStrategy
    /// @inheritdoc ILeverageLendingStrategy
    function realTvl() public view returns (uint tvl, bool trusted) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        return ALMFLib.realTvl(platform(), $);
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
        return ALMFLib.health(platform(), $);
    }

    /// @inheritdoc ILeverageLendingStrategy
    function getSupplyAndBorrowAprs() external view returns (uint supplyApr, uint borrowApr) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        return (0, 0); // todo
    }
//endregion ----------------------------------- ILeverageLendingStrategy

//region ----------------------------------- Strategy base
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        assets_ = $base._assets;
        amounts_ = new uint[](1);
        amounts_[0] = StrategyLib.balance(_getAToken()); // todo
    }

    /// @inheritdoc StrategyBase
    //slither-disable-next-line unused-return
    function _depositAssets(uint[] memory amounts, bool) internal override returns (uint value) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        address[] memory _assets = assets();

        value = ALMFLib.depositAssets($, $base, amounts[0], _assets[0]);
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();

        return _withdrawAssets($base._assets, value, receiver);
    }

    /// @inheritdoc StrategyBase
    //slither-disable-next-line unused-return
    function _withdrawAssets(
        address[] memory,
        uint value,
        address receiver
    ) internal override returns (uint[] memory amountsOut) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();

        amountsOut = ALMFLib.withdrawAssets(platform(), $, $base, value, receiver);
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax)
    internal
    pure
    override
    returns (uint[] memory amountsConsumed, uint value)
    {
        amountsConsumed = new uint[](1);
        amountsConsumed[0] = amountsMax[0];
        value = amountsMax[0];
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(
        address[] memory, /*assets_*/
        uint[] memory amountsMax
    ) internal pure override returns (uint[] memory amountsConsumed, uint value) {
        return _previewDepositAssets(amountsMax);
    }

    /// @inheritdoc StrategyBase
    function _processRevenue(
        address[] memory, /*assets_*/
        uint[] memory /*amountsRemaining*/
    ) internal pure override returns (bool needCompound) {
        needCompound = true;
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

        __assets = assets();
        (__amounts, __rewardAssets, __rewardAmounts) =
        ALMFLib._claimRevenue($, _getStrategyBaseStorage(), _getFarmingStrategyBaseStorage());
    }

    /// @inheritdoc StrategyBase
    function _compound() internal override {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();

        ALMFLib._compound(platform(), vault(), $, _getStrategyBaseStorage());
    }

    /// @inheritdoc StrategyBase
    function _depositUnderlying(uint amount) internal override returns (uint[] memory amountsConsumed) {
        // todo

        AlmfStrategyStorage storage $ = _getStorage();
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();

        amountsConsumed = _previewDepositUnderlying(amount);

        if ($.lastSharePrice == 0) {
            $.lastSharePrice = _getSharePrice($base._underlying);
        }
    }

    /// @inheritdoc StrategyBase
    function _withdrawUnderlying(uint amount, address receiver) internal override {
        // todo

        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        IERC20($base._underlying).safeTransfer(receiver, amount);
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
        earnedExchangeAsset = FarmingStrategyBase._liquidateRewards(exchangeAsset, rewardAssets_, rewardAmounts_);
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
    function _getStorage() internal pure returns (AlmfStrategyStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := AAVE_MERKL_FARM_STRATEGY_STORAGE_LOCATION
        }
    }

    function _getSharePrice(address u) internal view returns (uint) {
        IAToken aToken = IAToken(u);
        uint scaledBalance = aToken.scaledTotalSupply();
        return scaledBalance == 0 ? 0 : aToken.totalSupply() * 1e18 / scaledBalance;
    }

    function _getRevenue(
        uint newPrice,
        address u
    ) internal view returns (address[] memory __assets, uint[] memory amounts) {
        AlmfStrategyStorage storage $ = _getStorage();
        __assets = assets();
        amounts = new uint[](1);
        uint oldPrice = $.lastSharePrice;
        if (newPrice > oldPrice && oldPrice != 0) {
            // deposited asset balance
            uint scaledBalance = IAToken(u).scaledBalanceOf(address(this));

            // share price already takes into account accumulated interest
            amounts[0] = scaledBalance * (newPrice - oldPrice) / 1e18;
        }
    }

    function _generateDescription(address aToken) internal view returns (string memory) {
        //slither-disable-next-line calls-loop
        return string.concat(
            "Supply ",
            IERC20Metadata(IAToken(aToken).UNDERLYING_ASSET_ADDRESS()).symbol(),
            " to AAVE ",
            SharedLib.shortAddress(IAToken(aToken).POOL()),
            " with leverage, Merkl rewards"
        );
    }

    function _getAToken(FarmingStrategyBaseStorage storage $) internal view returns (address) {
        return _getFarm(platform(), $.farmId).addresses[0];
    }
//endregion ----------------------------------- Internal logic
}
