// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IIncentivesClaimingLogic} from "../integrations/silo/IIncentivesClaimingLogic.sol";
import {ISiloIncentivesControllerForVault} from "../integrations/silo/ISiloIncentivesControllerForVault.sol";
import {IVaultIncentivesModule} from "../integrations/silo/IVaultIncentivesModule.sol";
import {
    FarmingStrategyBase,
    StrategyBase,
    IFarmingStrategy,
    IFactory,
    StrategyLib,
    IPlatform
} from "./base/FarmingStrategyBase.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {FarmMechanicsLib} from "./libs/FarmMechanicsLib.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ISiloVault} from "../integrations/silo/ISiloVault.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SharedLib} from "./libs/SharedLib.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {VaultTypeLib} from "../core/libs/VaultTypeLib.sol";
import {IXSilo} from "../integrations/silo/IXSilo.sol";
import {MerklStrategyBase} from "./base/MerklStrategyBase.sol";

/// @title Supply asset to Silo V2 managed vault and earn farm rewards + rewards from Merkl
/// Changelog:
///   1.0.1: StrategyBase 2.6.0, fix getSpecificName
/// @author dvpublic (https://github.com/dvpublic)
contract SiloManagedMerklFarmStrategy is MerklStrategyBase, FarmingStrategyBase {
    using SafeERC20 for IERC20;
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.1";

    /// @dev Strategy logic ID used in this farm
    string internal constant STRATEGY_LOGIC_ID = StrategyIdLib.SILO_MANAGED_MERKL_FARM;

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

        ISiloVault siloVault = ISiloVault(farm.addresses[0]);
        address[] memory siloAssets = new address[](1);
        siloAssets[0] = siloVault.asset();

        __StrategyBase_init(addresses[0], STRATEGY_LOGIC_ID, addresses[1], siloAssets, address(0), 0);
        __FarmingStrategyBase_init(addresses[0], nums[0]);

        IERC20(siloAssets[0]).forceApprove(farm.addresses[0], type(uint).max);
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
    function supportedVaultTypes() external pure override returns (string[] memory types) {
        types = new string[](1);
        types[0] = VaultTypeLib.COMPOUNDING;
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
        string memory specific = _getStrategyBaseStorage().specific;
        if (bytes(specific).length != 0) {
            return (specific, true);
        }
        ISiloVault siloVault = _getSiloVault();
        string memory shortAddr = SharedLib.shortAddress(address(siloVault));
        return (string.concat(IERC20Metadata(siloVault.asset()).symbol(), " ", shortAddr), true);
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
    function description() external view returns (string memory) {
        IFactory.Farm memory farm = _getFarm();
        return _genDesc(farm);
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
    function maxWithdrawAssets(
        uint /*mode*/
    ) public view override returns (uint[] memory amounts) {
        ISiloVault siloVault = _getSiloVault();
        amounts = new uint[](1);
        amounts[0] = siloVault.maxWithdraw(address(this));
    }

    /// @inheritdoc IStrategy
    function poolTvl() public view virtual override returns (uint tvlUsd) {
        ISiloVault siloVault = _getSiloVault();

        address asset = siloVault.asset();
        IPriceReader priceReader = IPriceReader(IPlatform(platform()).priceReader());

        // get price of 1 amount of asset in USD with decimals 18
        // assume that {trusted} value doesn't matter here
        /// slither-disable-next-line ignore-unused-return
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
    function canFarm() external view override returns (bool) {
        IFactory.Farm memory farm = _getFarm();
        return farm.status == 0;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    //slither-disable-next-line unused-return
    function _depositAssets(
        uint[] memory amounts,
        bool /*claimRevenue*/
    ) internal override returns (uint value) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        value = amounts[0];
        if (value != 0) {
            _getSiloVault().deposit(value, address(this));
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
        address[] memory, /* _assets */
        uint value,
        address receiver
    ) internal override returns (uint[] memory amountsOut) {
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

        // ------------------- calculate earned amounts
        address[] memory farmAddresses = _getFarm().addresses;
        ISiloVault siloVault = ISiloVault(farmAddresses[0]);
        __amounts[0] = siloVault.convertToAssets(siloVault.balanceOf(address(this))) - $base.total;

        // ------------------- claim all available rewards
        siloVault.claimRewards();

        {
            IVaultIncentivesModule vim = IVaultIncentivesModule(siloVault.INCENTIVES_MODULE());
            address[] memory claimingLogics = vim.getAllIncentivesClaimingLogics();

            for (uint i; i < claimingLogics.length; ++i) {
                IIncentivesClaimingLogic logic = IIncentivesClaimingLogic(claimingLogics[i]);
                ISiloIncentivesControllerForVault c =
                    ISiloIncentivesControllerForVault(logic.VAULT_INCENTIVES_CONTROLLER());

                c.claimRewards(address(this));
            }
        }
        // Merkl rewards: assume they are added on the balance automatically

        // ------------------- xSilo => silo, collect all registered rewards to __rewardAmounts

        // We assume here that SILO is set as a reward token in farm settings
        // and xSilo is specified only in farmAddresses[1].
        // Such config is valid for the case when rewards are provided in xSilo.
        // It allows us to be able to keep xSilo on balance for any time without problems.
        // And we can exchange it on silo at any moment and get real (silo) rewards.
        // Currently we doesn't keep xSilo on balance - we always exchange it on silo instantly.

        address xSilo = farmAddresses[1];
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
    function _processRevenue(
        address[] memory, /*assets_*/
        uint[] memory /*amountsRemaining*/
    ) internal pure override returns (bool needCompound) {
        needCompound = true;
    }

    /// @inheritdoc StrategyBase
    function _compound() internal override {
        address[] memory _assets = assets();
        uint len = _assets.length;
        uint[] memory amounts = new uint[](len);

        //slither-disable-next-line uninitialized-local
        bool notZero; // true if there is any not zero value in {amounts}

        for (uint i; i < len; ++i) {
            amounts[i] = StrategyLib.balance(_assets[i]);
            if (amounts[i] != 0) {
                notZero = true;
                break;
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
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        assets_ = $base._assets;
        amounts_ = new uint[](1);
        amounts_[0] = $base.total;
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
            " to Silo managed vault + receive Merkl rewards",
            shortAddr
        );
    }

    function _getSiloVault() internal view returns (ISiloVault) {
        return ISiloVault(_getFarm().addresses[0]);
    }
}
