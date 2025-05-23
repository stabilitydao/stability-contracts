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

        address[] memory _assets = new address[](1);
        _assets[0] = IEVault(farm.addresses[1]).asset();
        __StrategyBase_init(
            addresses[0], StrategyIdLib.EULER_MERKL_FARM, addresses[1], _assets, farm.addresses[1], type(uint).max
        );
        IERC20(_assets[0]).forceApprove(farm.addresses[1], type(uint).max);

        __FarmingStrategyBase_init(addresses[0], nums[0]);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(MerklStrategyBase, FarmingStrategyBase)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IFarmingStrategy
    function canFarm() external view override returns (bool) {
        IFactory.Farm memory farm = _getFarm();
        return farm.status == 0;
    }

    /// @inheritdoc IStrategy
    function getRevenue() external view returns (address[] memory __assets, uint[] memory amounts) {
        console.log("getRevenue.1");
        __assets = _getFarmingStrategyBaseStorage()._rewardAssets;
        uint len = __assets.length;
        amounts = new uint[](len);
        for (uint i; i < len; ++i) {
            amounts[i] = StrategyLib.balance(__assets[i]);
            console.log("getRevenue", amounts[i]);
        }
        console.log("getRevenue.2");
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
    function getAssetsProportions() external pure returns (uint[] memory proportions) {
        proportions = EMFLib.getAssetsProportions();
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        //slither-disable-next-line too-many-digits
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x965fff), bytes3(0x000000)));
    }

    /// @inheritdoc IStrategy
    function autoCompoundingByUnderlyingProtocol() public view virtual override returns (bool) {
        return true;
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

    /// @inheritdoc IStrategy
    function isReadyForHardWork() external view returns (bool) {
        console.log("isReadyForHardWork");
        return total() != 0;
    }

    /// @inheritdoc IFarmingStrategy
    function farmMechanics() external pure returns (string memory) {
        return FarmMechanicsLib.MERKL;
    }

    /// @inheritdoc IStrategy
    function supportedVaultTypes() external pure override(StrategyBase) returns (string[] memory types) {
        types = new string[](1);
        types[0] = VaultTypeLib.COMPOUNDING;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _depositAssets(uint[] memory amounts, bool claimRevenue) internal override returns (uint value) {
        console.log("_depositAssets.1");
        value = EMFLib.depositAssets(
            amounts, claimRevenue, _getFarmingStrategyBaseStorage(), _getStrategyBaseStorage(), _getFarm()
        );
        console.log("_depositAssets.2");
    }

    /// @inheritdoc StrategyBase
    function _depositUnderlying(uint amount) internal override returns (uint[] memory amountsConsumed) {
        console.log("_depositUnderlying.1");
        return EMFLib.depositUnderlying(amount, _getStrategyBaseStorage());
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        console.log("_withdrawAssets.1", value);
        return EMFLib.withdrawAssets(value, receiver, _getFarm(), _getStrategyBaseStorage());
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(
        address[] memory /* assets_ */,
        uint value,
        address receiver
    ) internal override returns (uint[] memory amountsOut) {
        console.log("_withdrawAssets.2");
        return _withdrawAssets(value, receiver);
    }

    /// @inheritdoc StrategyBase
    function _withdrawUnderlying(uint amount, address receiver) internal override {
        console.log("_withdrawAssets.3");
        EMFLib.withdrawUnderlying(amount, receiver, _getFarm(), _getStrategyBaseStorage());
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
        console.log("_claimRevenue.1");
        (__assets, __amounts, __rewardAssets, __rewardAmounts) =
            EMFLib._claimRevenue(_getFarmingStrategyBaseStorage(), _getStrategyBaseStorage(), _getFarm());
        console.log("_claimRevenue.2");
    }

    /// @inheritdoc StrategyBase
    function _compound() internal override {}

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax)
        internal
        view
        override(StrategyBase)
        returns (uint[] memory amountsConsumed, uint value)
    {
        console.log("_previewDepositAssets.1");
        (amountsConsumed, value) = EMFLib.previewDepositAssets(amountsMax, _getStrategyBaseStorage());
        console.log("_previewDepositAssets.2");
    }

    function _previewDepositAssets(
        address[] memory /* assets_ */,
        uint[] memory amountsMax
    ) internal view virtual override returns (uint[] memory amountsConsumed, uint value) {
        return _previewDepositAssets(amountsMax);
    }

    /// @inheritdoc StrategyBase
    function _previewDepositUnderlying(uint amount) internal view override returns (uint[] memory amountsConsumed) {
        console.log("_previewDepositUnderlying.1");
        return EMFLib.previewDepositUnderlying(amount, _getStrategyBaseStorage());
    }

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        console.log("_assetsAmounts.1");
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        assets_ = $base._assets;
        address u = $base._underlying;
        amounts_ = new uint[](1);
        amounts_[0] = IEVault(u).convertToAssets(IERC20(u).balanceOf(address(this)));
        console.log("_assetsAmounts.2");
    }

    /// @inheritdoc StrategyBase
    function _processRevenue(
        address[] memory assets_,
        uint[] memory amountsRemaining
    ) internal virtual override returns (bool needCompound) {
        console.log("_processRevenue");
    }
}
