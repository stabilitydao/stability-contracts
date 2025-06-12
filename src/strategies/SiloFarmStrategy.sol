// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {VaultTypeLib} from "../core/libs/VaultTypeLib.sol";
import {
    FarmingStrategyBase,
    StrategyBase,
    IFarmingStrategy,
    IStrategy,
    IFactory,
    IControllable,
    StrategyLib,
    IPlatform
} from "./base/FarmingStrategyBase.sol";
import {ISiloVault} from "../integrations/silo/ISiloVault.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {FarmMechanicsLib} from "./libs/FarmMechanicsLib.sol";
import {ISiloIncentivesController} from "../integrations/silo/ISiloIncentivesController.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ISilo} from "../integrations/silo/ISilo.sol";
import {ISiloConfig} from "../integrations/silo/ISiloConfig.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";

/// @title Earns incentives and supply APR on Silo V2
/// Changelog:
///   1.0.3: getSpecificName update
///   1.0.2: FarmingStrategyBase 1.3.3
///   1.0.1: claimRevenue bugfix
/// @author 0xhokugava (https://github.com/0xhokugava)
contract SiloFarmStrategy is FarmingStrategyBase {
    using SafeERC20 for IERC20;
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.2";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function initialize(address[] memory addresses, uint[] memory nums, int24[] memory ticks) public initializer {
        if (addresses.length != 2 || nums.length != 1 || ticks.length != 0) {
            revert IControllable.IncorrectInitParams();
        }

        IFactory.Farm memory farm = _getFarm(addresses[0], nums[0]);
        if (farm.addresses.length != 2 || farm.nums.length != 0 || farm.ticks.length != 0) {
            revert IFarmingStrategy.BadFarm();
        }

        address[] memory siloAssets = new address[](1);
        ISilo siloVault = ISilo(farm.addresses[1]);
        siloAssets[0] = siloVault.asset();
        __StrategyBase_init(addresses[0], StrategyIdLib.SILO_FARM, addresses[1], siloAssets, address(0), 0);
        __FarmingStrategyBase_init(addresses[0], nums[0]);
        IERC20(siloAssets[0]).forceApprove(farm.addresses[1], type(uint).max);
        IERC20(farm.addresses[1]).forceApprove(farm.addresses[0], type(uint).max);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.SILO_FARM;
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
        addresses = new address[](0);
        ticks = new int24[](0);
        IFactory.Farm[] memory farms = IFactory(IPlatform(platform_).factory()).farms();
        uint len = farms.length;
        //slither-disable-next-line uninitialized-local
        uint _total;
        for (uint i; i < len; ++i) {
            IFactory.Farm memory farm = farms[i];
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, StrategyIdLib.SILO_FARM)) {
                ++_total;
            }
        }
        variants = new string[](_total);
        nums = new uint[](_total);
        _total = 0;
        for (uint i; i < len; ++i) {
            IFactory.Farm memory farm = farms[i];
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, StrategyIdLib.SILO_FARM)) {
                nums[_total] = i;
                variants[_total] = _genDesc(farm);
                ++_total;
            }
        }
    }

    /// @inheritdoc IStrategy
    function isHardWorkOnDepositAllowed() external pure returns (bool) {
        return true;
    }

    /// @inheritdoc IStrategy
    function isReadyForHardWork() external pure returns (bool isReady) {
        isReady = true;
    }

    /// @inheritdoc IFarmingStrategy
    function farmMechanics() external pure returns (string memory) {
        return FarmMechanicsLib.AUTO;
    }

    /// @inheritdoc IStrategy
    function poolTvl() public view virtual override returns (uint tvlUsd) {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        IERC4626 u = IERC4626(__$__._underlying);

        address asset = u.asset();
        IPriceReader priceReader = IPriceReader(IPlatform(platform()).priceReader());

        // get price of 1 amount of asset in USD with decimals 18
        // assume that {trusted} value doesn't matter here
        (uint price, ) = priceReader.getPrice(asset);

        return u.totalAssets() * price / (10**IERC20Metadata(asset).decimals());
    }

    /// @inheritdoc IStrategy
    function maxWithdrawAssets() public view override returns (uint[] memory amounts) {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        IERC4626 u = IERC4626(__$__._underlying);
        amounts = new uint[](1);
        amounts[0] = u.maxWithdraw(address(this));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   FARMING STRATEGY BASE                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

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
        if (value > 0) {
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
        __assets = assets();
        __amounts = new uint[](__assets.length);
        FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();
        __rewardAssets = $f._rewardAssets;
        uint rwLen = __rewardAssets.length;
        uint[] memory balanceBefore = new uint[](rwLen);
        __rewardAmounts = new uint[](rwLen);
        for (uint i; i < rwLen; ++i) {
            balanceBefore[i] = StrategyLib.balance(__rewardAssets[i]);
        }
        IFactory.Farm memory farm = _getFarm();
        ISilo siloVault = ISilo(farm.addresses[1]);
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        __amounts[0] = siloVault.convertToAssets(siloVault.balanceOf(address(this))) - $base.total;
        ISiloIncentivesController(farm.addresses[0]).claimRewards(address(this));
        for (uint i; i < rwLen; ++i) {
            __rewardAmounts[i] = StrategyLib.balance(__rewardAssets[i]) - balanceBefore[i];
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
