// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {LPStrategyBase, StrategyBase, IStrategy, ILPStrategy} from "./base/LPStrategyBase.sol";
import {FarmingStrategyBase, IFarmingStrategy} from "./base/FarmingStrategyBase.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IAmmAdapter} from "../interfaces/IAmmAdapter.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {VaultTypeLib} from "../core/libs/VaultTypeLib.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {ISolidlyPool} from "../integrations/solidly/ISolidlyPool.sol";
import {IXShadow} from "../integrations/shadow/IXShadow.sol";
import {ShFLib} from "./libs/ShFLib.sol";

/// @title Earn Shadow farm rewards by classic LPs
/// @author Jude (https://github.com/iammrjude)
contract ShadowFarmStrategy is LPStrategyBase, FarmingStrategyBase {
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
        if (farm.addresses.length != 3 || farm.nums.length != 0 || farm.ticks.length != 0) {
            revert IFarmingStrategy.BadFarm();
        }

        __LPStrategyBase_init(
            LPStrategyBaseInitParams({
                id: ShFLib.strategyLogicId(),
                platform: addresses[0],
                vault: addresses[1],
                pool: farm.pool,
                underlying: farm.pool
            })
        );

        __FarmingStrategyBase_init(addresses[0], nums[0]);

        address[] memory _assets = assets();
        IERC20(_assets[0]).forceApprove(farm.addresses[1], type(uint).max);
        IERC20(_assets[1]).forceApprove(farm.addresses[1], type(uint).max);
        IERC20(farm.pool).forceApprove(farm.addresses[0], type(uint).max);
        IERC20(farm.pool).forceApprove(farm.addresses[1], type(uint).max);
        address swapper = IPlatform(addresses[0]).swapper();
        IERC20(IXShadow(farm.addresses[2]).SHADOW()).forceApprove(swapper, type(uint).max);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(LPStrategyBase, FarmingStrategyBase)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IFarmingStrategy
    function canFarm() external view override returns (bool) {
        IFactory.Farm memory farm = _getFarm();
        return farm.status == 0;
    }

    /// @inheritdoc FarmingStrategyBase
    function stakingPool() external view override returns (address) {
        IFactory.Farm memory farm = _getFarm();
        return farm.addresses[0];
    }

    /// @inheritdoc ILPStrategy
    function ammAdapterId() public pure override returns (string memory) {
        return ShFLib.ammAdapterId();
    }

    /// @inheritdoc IStrategy
    function getRevenue() external pure returns (address[] memory __assets, uint[] memory amounts) {
        __assets = new address[](0);
        amounts = new uint[](0);
    }

    /// @inheritdoc IStrategy
    function initVariants(address platform_)
        public
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        (variants, addresses, nums, ticks) = ShFLib.initVariants(platform_);
    }

    /// @inheritdoc IStrategy
    function isHardWorkOnDepositAllowed() external pure returns (bool allowed) {
        allowed = true;
    }

    /// @inheritdoc IStrategy
    function isReadyForHardWork() external view returns (bool) {
        return total() != 0;
    }

    /// @inheritdoc IFarmingStrategy
    function farmMechanics() external pure returns (string memory) {
        return ShFLib.farmMechanics();
    }

    /// @inheritdoc IStrategy
    function supportedVaultTypes()
        external
        pure
        override(LPStrategyBase, StrategyBase)
        returns (string[] memory types)
    {
        types = new string[](1);
        types[0] = VaultTypeLib.COMPOUNDING;
    }

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return ShFLib.strategyLogicId();
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() public view returns (uint[] memory proportions) {
        ILPStrategy.LPStrategyBaseStorage storage $lp = _getLPStrategyBaseStorage();
        proportions = $lp.ammAdapter.getProportions($lp.pool);
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        //slither-disable-next-line too-many-digits
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x20c9e7), bytes3(0x000000)));
    }

    /// @inheritdoc IStrategy
    function getSpecificName() public view override returns (string memory, bool) {
        return (ISolidlyPool(pool()).stable() ? "sLP" : "vLP", false);
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();
        ILPStrategy.LPStrategyBaseStorage storage $lp = _getLPStrategyBaseStorage();
        IFactory.Farm memory farm = IFactory(IPlatform(platform()).factory()).farm($f.farmId);
        return ShFLib.generateDescription(farm, $lp.ammAdapter);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _depositAssets(uint[] memory amounts, bool) internal override returns (uint value) {
        return ShFLib.depositAssets(_getFarm(), assets(), _getStrategyBaseStorage(), amounts);
    }

    /// @inheritdoc StrategyBase
    function _depositUnderlying(uint amount) internal override returns (uint[] memory amountsConsumed) {
        return ShFLib.depositUnderlying(_getFarm(), _getStrategyBaseStorage(), amount);
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        return ShFLib.withdrawAssets(_getFarm(), assets(), _getStrategyBaseStorage(), value, receiver);
    }

    /// @inheritdoc StrategyBase
    function _withdrawUnderlying(uint amount, address receiver) internal override {
        ShFLib.withdrawUnderlying(_getFarm(), _getStrategyBaseStorage(), amount, receiver);
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
        (__assets, __amounts, __rewardAssets, __rewardAmounts) =
            ShFLib.claimRevenue(_getFarmingStrategyBaseStorage(), assets(), _getFarm());
    }

    /// @inheritdoc StrategyBase
    function _compound() internal override {
        uint[] memory amountsToDeposit = _swapForDepositProportion(getAssetsProportions()[0]);
        if (amountsToDeposit[0] > 2500 && amountsToDeposit[1] > 2500) {
            _depositAssets(amountsToDeposit, true);
        }
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax)
        internal
        view
        override(StrategyBase, LPStrategyBase)
        returns (uint[] memory amountsConsumed, uint value)
    {
        IAmmAdapter _adapter = IAmmAdapter(IPlatform(platform()).ammAdapter(keccak256(bytes(ammAdapterId()))).proxy);
        ILPStrategy.LPStrategyBaseStorage storage $lp = _getLPStrategyBaseStorage();
        (value, amountsConsumed) = _adapter.getLiquidityForAmounts($lp.pool, amountsMax);
    }

    /// @inheritdoc StrategyBase
    function _previewDepositUnderlying(uint amount) internal view override returns (uint[] memory amountsConsumed) {
        // TODO
    }

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        assets_ = assets();
        amounts_ = ShFLib.calcAssetsAmounts(total(), _getFarm());
    }
}
