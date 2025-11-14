// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/console.sol";
import {ALMFLib} from "./libs/ALMFLib.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {FarmMechanicsLib} from "./libs/FarmMechanicsLib.sol";
import {FarmingStrategyBase} from "./base/FarmingStrategyBase.sol";
import {IAToken} from "../integrations/aave/IAToken.sol";
import {IAaveAddressProvider} from "../integrations/aave/IAaveAddressProvider.sol";
import {IAavePriceOracle} from "../integrations/aave/IAavePriceOracle.sol";
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
import {IVault} from "../interfaces/IVault.sol";
import {ILeverageLendingStrategy} from "../interfaces/ILeverageLendingStrategy.sol";
import {IPool} from "../integrations/aave/IPool.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IUniswapV3FlashCallback} from "../integrations/uniswapv3/IUniswapV3FlashCallback.sol";
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
        if (farm.addresses.length != 3 || farm.nums.length != 3 || farm.ticks.length != 0) {
            revert IFarmingStrategy.BadFarm();
        }

        // slither-disable-next-line unused-return
        LeverageLendingStrategyBaseInitParams memory params;

        params.platform = addresses[0];
        params.strategyId = STRATEGY_LOGIC_ID;
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

        address pool = IAToken(params.lendingVault).POOL();
        IERC20(params.collateralAsset).forceApprove(pool, type(uint).max);
        IERC20(params.borrowAsset).forceApprove(pool, type(uint).max);

        address swapper = IPlatform(params.platform).swapper();
        IERC20(params.collateralAsset).forceApprove(swapper, type(uint).max);
        IERC20(params.borrowAsset).forceApprove(swapper, type(uint).max);

        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();

        // ------------------------------ Set up all params in use
        //        // Multiplier of flash amount for borrow on deposit. Default is 100_00 = 100%
        //        $.depositParam0 = 100_00;
        //        // Multiplier of borrow amount to take into account max flash loan fee in maxDeposit. Default is 99_80 = 99.8%
        //        $.depositParam1 = 99_80;

        // Multiplier of debt diff
        $.increaseLtvParam0 = 100_80;
        // Multiplier of swap borrow asset to collateral in flash loan callback
        $.increaseLtvParam1 = 99_00;
        // Multiplier of collateral diff
        $.decreaseLtvParam0 = 101_00;
        //
        // Swap price impact tolerance, ConstantsLib.DENOMINATOR
        $.swapPriceImpactTolerance0 = 1_000;
        $.swapPriceImpactTolerance1 = 1_000;

        // Leverage correction coefficient, INTERNAL_PRECISION. Default is 300 = 0.03
        $.withdrawParam0 = 300;

        //        // Multiplier of amount allowed to be deposited after withdraw. Default is 100_00 == 100% (deposit forbidden)
        //        $.withdrawParam1 = 100_00;
        //        // withdrawParam2 allows to disable withdraw through increasing ltv if leverage is near to target
        //        $.withdrawParam2 = 100_00;

        $.flashLoanKind = farm.nums[2];
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
    function getSpecificName() external view override returns (string memory, bool) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        IFactory.Farm memory farm = _getFarm();
        (uint targetMinLtv, uint targetMaxLtv) = ALMFLib._getFarmLtvConfig(farm);

        return (
            string.concat(
                IERC20Metadata($.borrowAsset).symbol(),
                " ",
                Strings.toString(targetMinLtv / 100),
                "-",
                Strings.toString(targetMaxLtv / 100)
            ),
            true
        );
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
    function total() public view override returns (uint) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        address _platform = platform();
        return ALMFLib.total(_platform, $, _getFarm(_platform, farmId()));
    }

    /// @inheritdoc IStrategy
    function getRevenue()
        public
        view
        override(IStrategy, LeverageLendingBase)
        returns (address[] memory assets_, uint[] memory amounts)
    {
        address aToken = _getAToken();
        (uint newPrice,) = _realSharePrice();
        (assets_, amounts) = _getRevenue(newPrice, aToken);
    }

    /// @inheritdoc IStrategy
    function isReadyForHardWork() external pure override(IStrategy, LeverageLendingBase) returns (bool isReady) {
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
    /// @dev Assume that all amount can be withdrawn always for simplicity. Implement later.
    function maxWithdrawAssets(uint mode) public pure override returns (uint[] memory amounts) {
        mode; // hide warning

        // for simplicity of v.1.0: any amount can be withdrawn
        return amounts;
    }

    /// @inheritdoc StrategyBase
    function _previewDepositUnderlying(uint amount) internal pure override returns (uint[] memory amountsConsumed) {
        amountsConsumed = new uint[](1);
        amountsConsumed[0] = amount;
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

    //endregion ----------------------------------- View functions

    //region ----------------------------------- ILeverageLendingStrategy
    /// @inheritdoc ILeverageLendingStrategy
    function realTvl() public view returns (uint tvl, bool trusted) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        address _platform = platform();
        return ALMFLib.realTvl(_platform, $, _getFarm(_platform, farmId()));
    }

    function _realSharePrice() internal view override returns (uint sharePrice, bool trusted) {
        uint _realTvl;
        (_realTvl, trusted) = realTvl();
        uint totalSupply = IERC20(vault()).totalSupply();
        if (totalSupply != 0) {
            sharePrice = _realTvl * 1e18 / totalSupply;
        }
        return (sharePrice, trusted);
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
        return ALMFLib.health(platform(), $, _getFarm());
    }

    /// @inheritdoc ILeverageLendingStrategy
    function getSupplyAndBorrowAprs() external view returns (uint supplyApr, uint borrowApr) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();
        return ALMFLib._getDepositAndBorrowAprs($.lendingVault, $.collateralAsset, $.borrowAsset);
    }

    function _rebalanceDebt(uint newLtv) internal override returns (uint resultLtv) {
        LeverageLendingBaseStorage storage $ = _getLeverageLendingBaseStorage();

        resultLtv = ALMFLib.rebalanceDebt(platform(), newLtv, $, _getFarm());
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
        AlmfStrategyStorage storage $a = _getStorage();
        FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();

        address aToken = $.lendingVault;
        (uint newPrice,) = _realSharePrice();
        if ($a.lastSharePrice == 0) {
            // first initialization of share price
            // we cannot do it in deposit() because total supply is used for calculation
            $a.lastSharePrice = newPrice;
        }
        (__assets, __amounts) = _getRevenue(newPrice, aToken);
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
        $base.total = total();
    }

    /// @inheritdoc StrategyBase
    function _compound() internal override(LeverageLendingBase, StrategyBase) {
        address[] memory _assets = assets();
        uint len = _assets.length;
        uint[] memory amounts = new uint[](len);

        //slither-disable-next-line uninitialized-local
        bool notZero;

        for (uint i; i < len; ++i) {
            amounts[i] = StrategyLib.balance(_assets[i]);
            if (amounts[i] != 0) {
                notZero = true;
            }
        }
        if (notZero) {
            _depositAssets(amounts, false);
        }

        StrategyBaseStorage storage $base = _getStrategyBaseStorage();

        // This strategy doesn't use $base.total at all
        // but StrategyBase expects it to be set in doHardWork in order to calculate aprCompound
        // so, we set it twice: here (new value) and in _claimRevenue (old value)
        $base.total = total();
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
        revert("no underlying"); // todo do we need to support it?
    }

    /// @inheritdoc StrategyBase
    function _withdrawUnderlying(
        uint,
        /*amount*/
        address /*receiver*/
    ) internal pure override {
        revert("no underlying"); // todo do we need to support it?
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
        pure
        override
        returns (uint[] memory amountsConsumed, uint value)
    {
        amountsConsumed = new uint[](1);
        amountsConsumed[0] = amountsMax[0];
        value = amountsMax[0]; // todo this value is incorrect
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

    function _getRevenue(
        uint newPrice,
        address u
    ) internal view returns (address[] memory __assets, uint[] memory amounts) {
        AlmfStrategyStorage storage $ = _getStorage();
        __assets = assets();

        // assume below that there is only 1 asset - collateral asset

        amounts = new uint[](1);
        uint oldPrice = $.lastSharePrice;

        if (newPrice > oldPrice && oldPrice != 0) {
            uint _totalSupply = IVault(vault()).totalSupply();
            uint price8 = IAavePriceOracle(
                    IAaveAddressProvider(IPool(IAToken(u).POOL()).ADDRESSES_PROVIDER()).getPriceOracle()
                ).getAssetPrice(__assets[0]);

            // share price already takes into account accumulated interest
            uint amountUSD18 = _totalSupply * (newPrice - oldPrice) / 1e18;
            amounts[0] = amountUSD18 * 1e8 * 10 ** IERC20Metadata(__assets[0]).decimals() / price8 / 1e18;
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

    function _getAToken() internal view returns (address) {
        FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();
        return _getFarm(platform(), $f.farmId).addresses[0];
    }

    //endregion ----------------------------------- Internal logic
}
