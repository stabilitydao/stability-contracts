// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC4626StrategyBase} from "./base/ERC4626StrategyBase.sol";
import {
FarmingStrategyBase,
StrategyBase,
StrategyLib,
IControllable,
IPlatform,
IFarmingStrategy,
IStrategy,
IFactory
} from "./base/FarmingStrategyBase.sol";
import {AmmAdapterIdLib} from "../adapters/libs/AmmAdapterIdLib.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {EMFLib} from "./libs/EMFLib.sol";
import {FarmMechanicsLib} from "./libs/FarmMechanicsLib.sol";
import {ICAmmAdapter} from "../interfaces/ICAmmAdapter.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IEVault} from "../integrations/euler/IEVault.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";
import {MerklStrategyBase} from "./base/MerklStrategyBase.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {VaultTypeLib} from "../core/libs/VaultTypeLib.sol";
import {console} from "forge-std/console.sol";

/// @title Lend asset on Euler and earn Merkl rewards
/// @author Jude (https://github.com/iammrjude)
/// @author dvpublic (https://github.com/dvpublic)
contract EulerMerklFarmStrategy is MerklStrategyBase, FarmingStrategyBase, ERC4626StrategyBase {
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
        if (farm.addresses.length != 2 || farm.nums.length != 0 || farm.ticks.length != 0) {
            revert IFarmingStrategy.BadFarm();
        }

        __ERC4626StrategyBase_init(StrategyIdLib.EULER_MERKL_FARM, addresses[0], addresses[1], farm.addresses[1]);
        __FarmingStrategyBase_init(addresses[0], nums[0]);
    }

    //region ----------------------- View functions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(MerklStrategyBase, FarmingStrategyBase, StrategyBase)
        returns (bool)
    {
        return
            FarmingStrategyBase.supportsInterface(interfaceId)
            || MerklStrategyBase.supportsInterface(interfaceId)
            || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IFarmingStrategy
    function canFarm() external view override returns (bool) {
        IFactory.Farm memory farm = _getFarm();
        return farm.status == 0;
    }

    /// @inheritdoc IStrategy
    function initVariants(address platform_)
        public
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        return EMFLib.initVariants(platform_, strategyLogicId());
    }

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.EULER_MERKL_FARM;
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        //slither-disable-next-line too-many-digits
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x965fff), bytes3(0x000000)));
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external view override returns (string memory, bool) {
        console.log("getSpecificName");
        IFactory.Farm memory farm = _getFarm();
        address asset = IEVault(farm.addresses[1]).asset();
        string memory symbol = IERC20Metadata(asset).symbol();
        return (symbol, false);
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        console.log("description.1");
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();
        IFactory.Farm memory farm = IFactory(IPlatform(platform()).factory()).farm($f.farmId);
        return EMFLib.generateDescription(farm);
    }

    /// @inheritdoc IStrategy
    function isHardWorkOnDepositAllowed() external pure returns (bool allowed) {
        console.log("isHardWorkOnDepositAllowed");
        allowed = false;
    }

    /// @inheritdoc IFarmingStrategy
    function farmMechanics() external pure returns (string memory) {
        return FarmMechanicsLib.MERKL;
    }

    /// @inheritdoc IStrategy
    function autoCompoundingByUnderlyingProtocol() public view virtual
    override (StrategyBase, ERC4626StrategyBase)
    returns (bool) {
        return true;
    }

    function total() public view
    override (StrategyBase, ERC4626StrategyBase)
    returns (uint) {
        return ERC4626StrategyBase.total();
    }

    /// @inheritdoc IStrategy
    function isReadyForHardWork() external view override (ERC4626StrategyBase, IStrategy) virtual returns (bool isReady) {
        (address[] memory __assets, uint[] memory amounts) = getRevenue();
        isReady = amounts[0] > ISwapper(IPlatform(platform()).swapper()).threshold(__assets[0]);
        console.log("isReadyForHardWork", isReady, amounts[0], amounts.length);
        return amounts[0] != 0; // todo
    }

    //endregion ----------------------- View functions

    //region ----------------------- Strategy base
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc ERC4626StrategyBase
    function _depositUnderlying(uint amount) internal override (ERC4626StrategyBase, StrategyBase) returns (uint[] memory amountsConsumed) {
        return ERC4626StrategyBase._depositUnderlying(amount);
    }

    /// @inheritdoc ERC4626StrategyBase
    function _withdrawUnderlying(uint amount, address receiver) internal override (ERC4626StrategyBase, StrategyBase) {
        ERC4626StrategyBase._withdrawUnderlying(amount, receiver);
    }

    /// @inheritdoc FarmingStrategyBase
    function _liquidateRewards(
        address exchangeAsset,
        address[] memory rewardAssets_,
        uint[] memory rewardAmounts_
    ) internal override(ERC4626StrategyBase, FarmingStrategyBase, StrategyBase) returns (uint earnedExchangeAsset) {
        console.log("_liquidateRewards");
        return FarmingStrategyBase._liquidateRewards(exchangeAsset, rewardAssets_, rewardAmounts_);
    }

    /// @inheritdoc StrategyBase
    function _claimRevenue()
    internal
    override (ERC4626StrategyBase, StrategyBase)
    returns (
        address[] memory __assets,
        uint[] memory __amounts,
        address[] memory __rewardAssets,
        uint[] memory __rewardAmounts
    )
    {
        ERC4626StrategyBaseStorage storage $ = _getERC4626StrategyBaseStorage();
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        address u = __$__._underlying;
        uint newSharePrice = _getSharePrice(u);
        (__assets, __amounts) = _getRevenue(newSharePrice, u);
        $.lastSharePrice = newSharePrice;
        (__rewardAssets, __rewardAmounts) = _getRewards();
        console.log("_claimRevenue", __amounts[0], __rewardAmounts[0]);
    }
    //endregion ----------------------- Strategy base

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/


    function _getRewards() internal view returns (address[] memory __assets, uint[] memory amounts) {
        // Merkl rewards: assume they are added on the balance automatically
        __assets = _getFarmingStrategyBaseStorage()._rewardAssets;
        uint len = __assets.length;
        amounts = new uint[](len);
        for (uint i; i < len; ++i) {
            amounts[i] = StrategyLib.balance(__assets[i]);
        }
    }
}
