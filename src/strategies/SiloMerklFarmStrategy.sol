// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./libs/SharedLib.sol";
import {
    FarmingStrategyBase,
    StrategyBase,
    IFarmingStrategy,
    IFactory,
    StrategyLib,
    IPlatform
} from "./base/FarmingStrategyBase.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {FarmMechanicsLib} from "./libs/FarmMechanicsLib.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";
import {ISiloConfig} from "../integrations/silo/ISiloConfig.sol";
import {ISiloIncentivesController} from "../integrations/silo/ISiloIncentivesController.sol";
import {ISilo} from "../integrations/silo/ISilo.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {MerklStrategyBase} from "./base/MerklStrategyBase.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {VaultTypeLib} from "../core/libs/VaultTypeLib.sol";
import {IXSilo} from "../integrations/silo/IXSilo.sol";

/// @title Supply asset to Silo V2 and earn farm rewards from Silo and Merkl
/// Changelog:
/// @author dvpublic (https://github.com/dvpublic)
contract SiloFarmStrategy is MerklStrategyBase, FarmingStrategyBase {
    using SafeERC20 for IERC20;
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    /// @dev Strategy logic ID used in this farm
    string internal constant STRATEGY_LOGIC_ID = StrategyIdLib.SILO_MERKL_FARM;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function initialize(address[] memory addresses, uint[] memory nums, int24[] memory ticks) public initializer {
        if (addresses.length != 2 || nums.length != 1 || ticks.length != 0) {
            revert IControllable.IncorrectInitParams();
        }

        IFactory.Farm memory farm = _getFarm(addresses[0], nums[0]);
        if (farm.addresses.length != 3 || farm.nums.length != 1 || farm.ticks.length != 0) {
            revert IFarmingStrategy.BadFarm();
        }

        address[] memory siloAssets = new address[](1);
        ISilo siloVault = ISilo(farm.addresses[1]);
        siloAssets[0] = siloVault.asset();

        __StrategyBase_init(addresses[0], STRATEGY_LOGIC_ID, addresses[1], siloAssets, address(0), 0);
        __FarmingStrategyBase_init(addresses[0], nums[0]);

        IERC20(siloAssets[0]).forceApprove(farm.addresses[1], type(uint).max);
        IERC20(farm.addresses[1]).forceApprove(farm.addresses[0], type(uint).max);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return STRATEGY_LOGIC_ID;
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x00d395), bytes3(0x000000)));
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        IFactory.Farm memory farm = _getFarm();
        return _genDesc(farm);
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() external pure returns (uint[] memory proportions) {
        proportions = new uint[](1);
        proportions[0] = 1e18;
    }

    /// @inheritdoc IStrategy
    function getRevenue() external view returns (address[] memory __assets, uint[] memory amounts) {}

    /// @inheritdoc IStrategy
    function getSpecificName() external view override returns (string memory, bool) {
        return (CommonLib.u2s(_getMarketId()), true);
    }

    /// @inheritdoc IStrategy
    function supportedVaultTypes() external pure override returns (string[] memory types) {
        types = new string[](1);
        types[0] = VaultTypeLib.COMPOUNDING;
    }

    /// @inheritdoc IStrategy
    function initVariants(address platform_)
        public
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        /// slither-disable-next-line ignore-unused-return
        return SharedLib.initVariantsForFarm(platform_, STRATEGY_LOGIC_ID, _genDesc);
    }

    /// @inheritdoc IStrategy
    function isHardWorkOnDepositAllowed() external pure returns (bool) {
        return false;
    }

    /// @inheritdoc IStrategy
    function isReadyForHardWork() external pure returns (bool isReady) {
        isReady = true;
    }

    /// @inheritdoc IStrategy
    function maxWithdrawAssets(uint /*mode*/ ) public view override returns (uint[] memory amounts) {
        IFactory.Farm memory farm = _getFarm();
        ISilo siloVault = ISilo(farm.addresses[1]);

        amounts = new uint[](1);
        amounts[0] = siloVault.maxWithdraw(address(this));
    }

    /// @inheritdoc IStrategy
    function poolTvl() public view virtual override returns (uint tvlUsd) {
        IFactory.Farm memory farm = _getFarm();
        ISilo siloVault = ISilo(farm.addresses[1]);

        address asset = siloVault.asset();
        IPriceReader priceReader = IPriceReader(IPlatform(platform()).priceReader());

        // get price of 1 amount of asset in USD with decimals 18
        // assume that {trusted} value doesn't matter here
        (uint price,) = priceReader.getPrice(asset);

        return siloVault.totalAssets() * price / (10 ** IERC20Metadata(asset).decimals());
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
    public
    view
    override(MerklStrategyBase, FarmingStrategyBase)
    returns (bool)
    {
        return FarmingStrategyBase.supportsInterface(interfaceId) || MerklStrategyBase.supportsInterface(interfaceId)
            || super.supportsInterface(interfaceId);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   FARMING STRATEGY BASE                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IFarmingStrategy
    function farmMechanics() external pure returns (string memory) {
        return FarmMechanicsLib.AUTO;
    }

    /// @inheritdoc IFarmingStrategy
    function canFarm() external pure override returns (bool) {
        return true;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    //slither-disable-next-line unused-return
    function _depositAssets(uint[] memory amounts, bool /*claimRevenue*/ ) internal override returns (uint value) {
        IFactory.Farm memory farm = _getFarm();
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        ISilo siloVault = ISilo(farm.addresses[1]);
        value = amounts[0];
        if (value != 0) {
            siloVault.deposit(value, address(this), ISilo.CollateralType.Collateral);
            $base.total += value;
        }
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        StrategyBaseStorage storage _$_ = _getStrategyBaseStorage();
        return _withdrawAssets(_$_._assets, value, receiver);
    }

    /// @inheritdoc StrategyBase
    //slither-disable-next-line unused-return
    function _withdrawAssets(
        address[] memory, // _assets
        uint value,
        address receiver
    ) internal override returns (uint[] memory amountsOut) {
        IFactory.Farm memory farm = _getFarm();
        ISilo siloVault = ISilo(farm.addresses[1]);
        uint toWithdraw = value;
        if (address(this) == receiver) {
            toWithdraw--;
        }
        siloVault.withdraw(toWithdraw, receiver, address(this), ISilo.CollateralType.Collateral);
        amountsOut = new uint[](1);
        amountsOut[0] = value;
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        $base.total -= value;
    }

    /// @inheritdoc StrategyBase
    function _liquidateRewards(
        address exchangeAsset,
        address[] memory rewardAssets_,
        uint[] memory rewardAmounts_
    ) internal override(FarmingStrategyBase, StrategyBase) returns (uint earnedExchangeAsset) {
        earnedExchangeAsset = FarmingStrategyBase._liquidateRewards(exchangeAsset, rewardAssets_, rewardAmounts_);
    }

    /// @inheritdoc StrategyBase
    //slither-disable-next-line unused-return
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
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();

        __assets = assets();
        __amounts = new uint[](__assets.length);

        __rewardAssets = $f._rewardAssets;
        uint lenRewards = __rewardAssets.length;
        __rewardAmounts = new uint[](lenRewards);

        // Merkl rewards: assume they are added on the balance automatically
        // So, we don't take into accounts "balance before" - assume all balance is rewards

        IFactory.Farm memory farm = _getFarm();
        ISilo siloVault = ISilo(farm.addresses[1]);
        __amounts[0] = siloVault.convertToAssets(siloVault.balanceOf(address(this))) - $base.total;
        ISiloIncentivesController(farm.addresses[0]).claimRewards(address(this));

        address xSilo = farm.addresses[1];
        address silo = xSilo != address(0) ? IXSilo(xSilo).asset() : address(0);

        for (uint i; i < lenRewards; ++i) {
            __rewardAmounts[i] = StrategyLib.balance(__rewardAssets[i]);
            if (__rewardAssets[i] == silo && xSilo != address(0)) {
                uint amountXSilo = StrategyLib.balance(xSilo);
                if (amountXSilo != 0) {
                    // instant exit with penalty 50%
                    __rewardAmounts[i] += IXSilo(xSilo).redeemSilo(amountXSilo, 0);
                }
            }
        }

    }

    /// @inheritdoc StrategyBase
    function _compound() internal override {
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
        IFactory.Farm memory farm = _getFarm();
        ISilo siloVault = ISilo(farm.addresses[1]);
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        $base.total = siloVault.convertToAssets(siloVault.balanceOf(address(this)));
        if (notZero) {
            _depositAssets(amounts, false);
        }
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
    function _previewDepositAssets(
        address[] memory, /*assets_*/
        uint[] memory amountsMax
    ) internal pure override(StrategyBase) returns (uint[] memory amountsConsumed, uint value) {
        return _previewDepositAssets(amountsMax);
    }

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        StrategyBaseStorage storage _$_ = _getStrategyBaseStorage();
        assets_ = _$_._assets;
        amounts_ = new uint[](1);
        amounts_[0] = _$_.total;
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

    function _genDesc(IFactory.Farm memory farm) internal view returns (string memory) {
        return string.concat(
            "Earn ",
            CommonLib.implode(CommonLib.getSymbols(farm.rewardAssets), ", "),
            " and supply APR by lending ",
            IERC20Metadata(ISilo(farm.addresses[1]).asset()).symbol(),
            " to Silo V2 ",
            CommonLib.u2s(_getMarketId())
        );
    }

    function _getMarketId() internal view returns (uint marketId) {
        IFactory.Farm memory farm = _getFarm();
        marketId = ISiloConfig(ISilo(farm.addresses[1]).config()).SILO_ID();
    }
}
