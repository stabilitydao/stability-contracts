// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Test.sol";
import {IIncentivesClaimingLogic} from "../integrations/silo/IIncentivesClaimingLogic.sol";
import {ISiloIncentivesControllerForVault} from "../integrations/silo/ISiloIncentivesControllerForVault.sol";
import {IVaultIncentivesModule} from "../integrations/silo/IVaultIncentivesModule.sol";
import {IDistributionManager} from "../integrations/silo/IDistributionManager.sol";
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
import {CommonLib} from "../core/libs/CommonLib.sol";
import {FarmMechanicsLib} from "./libs/FarmMechanicsLib.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISiloConfig} from "../integrations/silo/ISiloConfig.sol";
import {ISiloIncentivesController} from "../integrations/silo/ISiloIncentivesController.sol";
import {ISiloVault} from "../integrations/silo/ISiloVault.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SharedLib} from "./libs/SharedLib.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {VaultTypeLib} from "../core/libs/VaultTypeLib.sol";

/// @title Supply asset to Silo V2 managed vault and earn farm rewards
/// @author dvpublic (https://github.com/dvpublic)
contract SiloManagedFarmStrategy is FarmingStrategyBase {
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
        if (addresses.length != 2 || nums.length != 1 || ticks.length != 0) {
            revert IControllable.IncorrectInitParams();
        }

        IFactory.Farm memory farm = _getFarm(addresses[0], nums[0]);
        if (farm.addresses.length != 1 || farm.nums.length != 0 || farm.ticks.length != 0) {
            revert IFarmingStrategy.BadFarm();
        }

        ISiloVault siloVault = ISiloVault(farm.addresses[0]);
        address[] memory siloAssets = new address[](1);
        siloAssets[0] = siloVault.asset();

        __StrategyBase_init(addresses[0], StrategyIdLib.SILO_MANAGED_FARM, addresses[1], siloAssets, address(0), 0);
        __FarmingStrategyBase_init(addresses[0], nums[0]);

        IERC20(siloAssets[0]).forceApprove(farm.addresses[0], type(uint).max);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.SILO_MANAGED_FARM;
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
        ISiloVault siloVault = _getSiloVault();
        string memory shortAddr = SharedLib.shortAddress(address(siloVault));
        return (string.concat(IERC20Metadata(siloVault.asset()).symbol(), " ", shortAddr), true);
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
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, StrategyIdLib.SILO_MANAGED_FARM)) {
                ++_total;
            }
        }
        variants = new string[](_total);
        nums = new uint[](_total);
        _total = 0;
        for (uint i; i < len; ++i) {
            IFactory.Farm memory farm = farms[i];
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, StrategyIdLib.SILO_MANAGED_FARM)) {
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
        console.log("_depositAssets.SiloManagedFarmStrategy", amounts[0]);
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        value = amounts[0];
        if (value != 0) {
            _getSiloVault().deposit(value, address(this));
            $base.total += value;
        }
        console.log("_depositAssets.SiloManagedFarmStrategy.value", value, $base.total);
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        StrategyBaseStorage storage _$_ = _getStrategyBaseStorage();
        return _withdrawAssets(_$_._assets, value, receiver);
    }

    /// @inheritdoc StrategyBase
    //slither-disable-next-line unused-return
    function _withdrawAssets(
        address[] memory, /* _assets */
        uint value,
        address receiver
    ) internal override returns (uint[] memory amountsOut) {
        console.log("_withdrawAssets.SiloManagedFarmStrategy", value);
        uint toWithdraw = value;
        if (address(this) == receiver) {
            // same logic as in SiloFarmStrategy
            toWithdraw--;
        }
        _getSiloVault().withdraw(toWithdraw, receiver, address(this));

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

        // ------------------- get current balance of all registered rewards
        uint rwLen = __rewardAssets.length;
        uint[] memory balanceBefore = new uint[](rwLen);
        __rewardAmounts = new uint[](rwLen);
        for (uint i; i < rwLen; ++i) {
            balanceBefore[i] = StrategyLib.balance(__rewardAssets[i]);
        }

        // ------------------- calculate earned amounts
        ISiloVault siloVault = _getSiloVault();
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        __amounts[0] = siloVault.convertToAssets(siloVault.balanceOf(address(this))) - $base.total;

        // ------------------- claim all available rewards
        siloVault.claimRewards();

        IVaultIncentivesModule vim = IVaultIncentivesModule(siloVault.INCENTIVES_MODULE());
        address[] memory claimingLogics = vim.getAllIncentivesClaimingLogics();

        for (uint i; i < claimingLogics.length; ++i) {
            IIncentivesClaimingLogic logic = IIncentivesClaimingLogic(claimingLogics[i]);
            ISiloIncentivesControllerForVault c = ISiloIncentivesControllerForVault(logic.VAULT_INCENTIVES_CONTROLLER());

            //IDistributionManager.AccruedRewards[] memory accruedRewards =
            c.claimRewards(address(this));
        }

        // ------------------- take into account only rewards registered in the farm
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

        ISiloVault siloVault = _getSiloVault();
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
        string memory shortAddr = SharedLib.shortAddress(farm.addresses[0]);
        return string.concat(
            "Earn ",
            CommonLib.implode(CommonLib.getSymbols(farm.rewardAssets), ", "),
            " and supply APR by lending ",
            IERC20Metadata(ISiloVault(farm.addresses[0]).asset()).symbol(),
            " to Silo managed vault",
            shortAddr
        );
    }

    function _getSiloVault() internal view returns (ISiloVault) {
        return ISiloVault(_getFarm().addresses[0]);
    }
}
