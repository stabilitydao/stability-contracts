// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LPStrategyBase, ILPStrategy, IStrategy, IERC165, StrategyBase, VaultTypeLib} from "./base/LPStrategyBase.sol";
import {MerklStrategyBase} from "./base/MerklStrategyBase.sol";
import {
    FarmingStrategyBase,
    IFarmingStrategy,
    IControllable,
    IFactory,
    IPlatform,
    StrategyLib
} from "./base/FarmingStrategyBase.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {FarmMechanicsLib} from "./libs/FarmMechanicsLib.sol";
import {UniswapV3MathLib} from "./libs/UniswapV3MathLib.sol";
import {ALMPositionNameLib} from "./libs/ALMPositionNameLib.sol";
import {IUniProxy} from "../integrations/gamma/IUniProxy.sol";
import {IHypervisor} from "../integrations/gamma/IHypervisor.sol";
import {IUniswapV3Pool} from "../integrations/uniswapv3/IUniswapV3Pool.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {AmmAdapterIdLib} from "../adapters/libs/AmmAdapterIdLib.sol";
import {GUMFLib} from "./libs/GUMFLib.sol";

/// @title Earning Merkl rewards on Uniswap V3 by underlying Gamma Hypervisor
/// Changelog
///   1.6.2: Add maxDeploy, use StrategyBase 2.5.0 - #330
///   1.6.1: Use StrategyBase 2.4.0 - add default poolTvl, maxWithdrawAssets
///   1.6.0: Use StrategyBase 2.3.0 - add fuseMode
///   1.5.0: decrease code size
/// @author Alien Deployer (https://github.com/a17)
/// @author Hcrypto7 (https://github.com/Hcrypto7)
contract GammaUniswapV3MerklFarmStrategy is LPStrategyBase, MerklStrategyBase, FarmingStrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.6.2";

    uint internal constant _PRECISION = 1e36;

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.GammaUniswapV3MerklFarmStrategy")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant GAMMA_UNISWAPV3_MERKL_FARM_STRATEGY_STORAGE_LOCATION =
        0x54e0a6796044fbbedf8a0ca0f0b49138f4aea6a1bbbefa8f8ebd68bc7b577000;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.GammaUniswapV3MerklFarmStrategy
    struct GammaUniswapV3FarmStrategyStorage {
        IUniProxy uniProxy;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function initialize(address[] memory addresses, uint[] memory nums, int24[] memory ticks) public initializer {
        if (addresses.length != 2 || nums.length != 1 || ticks.length != 0) {
            revert IControllable.IncorrectInitParams();
        }

        IFactory.Farm memory farm = _getFarm(addresses[0], nums[0]);
        if (farm.addresses.length != 2 || farm.nums.length != 1 || farm.ticks.length != 0) {
            revert IFarmingStrategy.BadFarm();
        }
        GammaUniswapV3FarmStrategyStorage storage $ = _getStorage();
        $.uniProxy = IUniProxy(farm.addresses[0]);

        __LPStrategyBase_init(
            LPStrategyBaseInitParams({
                id: StrategyIdLib.GAMMA_UNISWAPV3_MERKL_FARM,
                platform: addresses[0],
                vault: addresses[1],
                pool: farm.pool,
                underlying: farm.addresses[1]
            })
        );

        __FarmingStrategyBase_init(addresses[0], nums[0]);

        address[] memory _assets = assets();
        IERC20(_assets[0]).forceApprove(farm.addresses[1], type(uint).max);
        IERC20(_assets[1]).forceApprove(farm.addresses[1], type(uint).max);

        // console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.GammaUniswapV3MerklFarmStrategy")) - 1)) & ~bytes32(uint256(0xff)));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(LPStrategyBase, MerklStrategyBase, FarmingStrategyBase)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IFarmingStrategy
    function canFarm() external view override returns (bool) {
        IFactory.Farm memory farm = _getFarm();
        return farm.status == 0;
    }

    /// @inheritdoc ILPStrategy
    function ammAdapterId() public pure override returns (string memory) {
        return AmmAdapterIdLib.UNISWAPV3;
    }

    /// @inheritdoc IStrategy
    function getRevenue() external view returns (address[] memory __assets, uint[] memory amounts) {
        __assets = _getFarmingStrategyBaseStorage()._rewardAssets;
        uint len = __assets.length;
        amounts = new uint[](len);
        for (uint i; i < len; ++i) {
            amounts[i] = StrategyLib.balance(__assets[i]);
        }
    }

    /// @inheritdoc IStrategy
    function initVariants(address platform_)
        public
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        return GUMFLib.initVariants(platform_, strategyLogicId(), ammAdapterId());
    }

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.GAMMA_UNISWAPV3_MERKL_FARM;
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() external view returns (uint[] memory proportions) {
        proportions = new uint[](2);
        proportions[0] = _getProportion0(pool());
        proportions[1] = 1e18 - proportions[0];
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0xde43ff), bytes3(0x140414)));
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external view override returns (string memory, bool) {
        IFactory.Farm memory farm = _getFarm();
        return (ALMPositionNameLib.getName(farm.nums[0]), true);
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();
        ILPStrategy.LPStrategyBaseStorage storage $lp = _getLPStrategyBaseStorage();
        IFactory.Farm memory farm = IFactory(IPlatform(platform()).factory()).farm($f.farmId);
        return GUMFLib.generateDescription(farm, $lp.ammAdapter);
    }

    /// @inheritdoc IStrategy
    function isHardWorkOnDepositAllowed() external pure returns (bool allowed) {}

    /// @inheritdoc IStrategy
    function isReadyForHardWork() external view returns (bool) {
        FarmingStrategyBaseStorage storage _$_ = _getFarmingStrategyBaseStorage();
        return StrategyLib.assetsAreOnBalance(_$_._rewardAssets);
    }

    /// @inheritdoc IFarmingStrategy
    function farmMechanics() external pure returns (string memory) {
        return FarmMechanicsLib.MERKL;
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

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _depositAssets(uint[] memory amounts, bool claimRevenue) internal override returns (uint value) {
        GammaUniswapV3FarmStrategyStorage storage $ = _getStorage();
        FarmingStrategyBaseStorage storage _$ = _getFarmingStrategyBaseStorage();
        StrategyBaseStorage storage __$ = _getStrategyBaseStorage();
        if (claimRevenue) {
            (,,, uint[] memory rewardAmounts) = _claimRevenue();
            uint len = rewardAmounts.length;
            // nosemgrep
            for (uint i; i < len; ++i) {
                // nosemgrep
                _$._rewardsOnBalance[i] += rewardAmounts[i];
            }
        }
        //slither-disable-next-line uninitialized-local
        uint[4] memory minIn;
        value = $.uniProxy.deposit(amounts[0], amounts[1], address(this), __$._underlying, minIn);
        __$.total += value;
    }

    /// @inheritdoc StrategyBase
    function _depositUnderlying(uint amount) internal override returns (uint[] memory amountsConsumed) {
        StrategyBaseStorage storage _$ = _getStrategyBaseStorage();
        amountsConsumed = _previewDepositUnderlying(amount);
        _$.total += amount;
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        // GammaUniswapV3FarmStrategyStorage storage $ = _getGammaQuickStorage();
        StrategyBaseStorage storage _$ = _getStrategyBaseStorage();
        amountsOut = new uint[](2);
        _$.total -= value;
        //slither-disable-next-line uninitialized-local
        uint[4] memory minAmounts;
        (amountsOut[0], amountsOut[1]) =
            IHypervisor(_$._underlying).withdraw(value, receiver, address(this), minAmounts);
    }

    /// @inheritdoc StrategyBase
    function _withdrawUnderlying(uint amount, address receiver) internal override {
        StrategyBaseStorage storage _$ = _getStrategyBaseStorage();
        IERC20(_$._underlying).safeTransfer(receiver, amount);
        _$.total -= amount;
    }

    /// @inheritdoc StrategyBase
    function _claimRevenue()
        internal
        view
        override
        returns (
            address[] memory __assets,
            uint[] memory __amounts,
            address[] memory __rewardAssets,
            uint[] memory __rewardAmounts
        )
    {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        FarmingStrategyBaseStorage storage _$_ = _getFarmingStrategyBaseStorage();
        __assets = __$__._assets;
        __rewardAssets = _$_._rewardAssets;
        __amounts = new uint[](2);
        uint rwLen = __rewardAssets.length;
        __rewardAmounts = new uint[](rwLen);
        for (uint i; i < rwLen; ++i) {
            __rewardAmounts[i] = StrategyLib.balance(__rewardAssets[i]);
        }
    }

    /// @inheritdoc StrategyBase
    function _compound() internal override {
        (uint[] memory amountsToDeposit) = _swapForDepositProportion(_getProportion0(pool()));
        // nosemgrep
        if (amountsToDeposit[0] > 1 && amountsToDeposit[1] > 1) {
            uint valueToReceive;
            (amountsToDeposit, valueToReceive) = _previewDepositAssets(amountsToDeposit);
            if (valueToReceive > 10) {
                _depositAssets(amountsToDeposit, false);
            }
        }
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax)
        internal
        view
        override(StrategyBase, LPStrategyBase)
        returns (uint[] memory amountsConsumed, uint value)
    {
        GammaUniswapV3FarmStrategyStorage storage $ = _getStorage();
        StrategyBaseStorage storage _$ = _getStrategyBaseStorage();
        amountsConsumed = new uint[](2);
        address[] memory _assets = assets();
        address underlying_ = _$._underlying;

        (uint amount1Start, uint amount1End) = $.uniProxy.getDepositAmount(underlying_, _assets[0], amountsMax[0]);
        IFactory.Farm memory farm = _getFarm();

        if (farm.nums[0] == ALMPositionNameLib.STABLE) {
            _handleStableAmounts(amountsMax, $, underlying_, _assets, amount1Start, amount1End, amountsConsumed);
        } else {
            _handleNonStableAmounts(amountsMax, $, underlying_, _assets, amount1Start, amount1End, amountsConsumed);
        }

        // calculate shares
        value = _calculateShares(amountsConsumed, underlying_);
    }

    function _handleStableAmounts(
        uint[] memory amountsMax,
        GammaUniswapV3FarmStrategyStorage storage $,
        address underlying_,
        address[] memory assets_,
        uint amount1Start,
        uint amount1End,
        uint[] memory amountsConsumed
    ) internal view {
        amountsConsumed[1] = amountsMax[1];
        amountsConsumed[0] = amountsMax[0];
        (, uint amount0End) = $.uniProxy.getDepositAmount(underlying_, assets_[1], amountsMax[1]);

        // Inline the assignment and condition with a ternary operator
        amountsConsumed[1] = (amountsMax[1] > amount1End) ? amount1End : amountsMax[1];

        // Check the second condition within another ternary operation
        (amountsMax[1] <= amount1Start) ? amountsConsumed[0] = amount0End : amountsConsumed[0];

        // Set amountsConsumed[1] to amountsMax[1] only if the second condition holds true
        amountsConsumed[1] = (amountsMax[1] <= amount1Start) ? amountsMax[1] : amountsConsumed[1];

        // Ensure amountsConsumed[0] does not exceed amount0End
        amountsConsumed[0] = (amountsConsumed[0] > amount0End) ? amount0End : amountsConsumed[0];
    }

    function _handleNonStableAmounts(
        uint[] memory amountsMax,
        GammaUniswapV3FarmStrategyStorage storage $,
        address underlying_,
        address[] memory assets_,
        uint amount1Start,
        uint amount1End,
        uint[] memory amountsConsumed
    ) internal view {
        if (amountsMax[1] > amount1End) {
            amountsConsumed[0] = amountsMax[0];
            amountsConsumed[1] = amount1End;
        } else if (amountsMax[1] <= amount1Start) {
            (uint amount0Start, uint amount0End) = $.uniProxy.getDepositAmount(underlying_, assets_[1], amountsMax[1]);
            amountsConsumed[0] = (amount0End + amount0Start) / 2;
            amountsConsumed[1] = amountsMax[1];
        } else {
            amountsConsumed[0] = amountsMax[0];
            amountsConsumed[1] = amountsMax[1];
        }
    }

    function _calculateShares(uint[] memory amountsConsumed, address underlying_) internal view returns (uint value) {
        IHypervisor hypervisor = IHypervisor(underlying_);
        //slither-disable-next-line unused-return
        (, int24 tick,,,,,) = IUniswapV3Pool(pool()).slot0();
        uint160 sqrtPrice = UniswapV3MathLib.getSqrtRatioAtTick(tick);
        uint price = UniswapV3MathLib.mulDiv(uint(sqrtPrice) * uint(sqrtPrice), _PRECISION, 2 ** (96 * 2));
        (uint pool0, uint pool1) = hypervisor.getTotalAmounts();

        value = amountsConsumed[1] + (amountsConsumed[0] * price / _PRECISION);
        uint pool0PricedInToken1 = pool0 * price / _PRECISION;
        value = value * hypervisor.totalSupply() / (pool0PricedInToken1 + pool1);
    }

    /// @inheritdoc StrategyBase
    function _previewDepositUnderlying(uint amount) internal view override returns (uint[] memory amountsConsumed) {
        IHypervisor hypervisor = IHypervisor(_getStrategyBaseStorage()._underlying);
        (uint pool0, uint pool1) = hypervisor.getTotalAmounts();
        uint _total = hypervisor.totalSupply();
        amountsConsumed = new uint[](2);
        amountsConsumed[0] = amount * pool0 / _total;
        amountsConsumed[1] = amount * pool1 / _total;
    }

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        StrategyBaseStorage storage $ = _getStrategyBaseStorage();
        assets_ = $._assets;
        amounts_ = new uint[](2);
        uint _total = $.total;
        if (_total > 0) {
            IHypervisor hypervisor = IHypervisor($._underlying);
            (amounts_[0], amounts_[1]) = hypervisor.getTotalAmounts();
            uint totalInHypervisor = hypervisor.totalSupply();
            (amounts_[0], amounts_[1]) =
                (amounts_[0] * _total / totalInHypervisor, amounts_[1] * _total / totalInHypervisor);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev proportion of 1e18
    function _getProportion0(address pool_) internal view returns (uint) {
        IHypervisor hypervisor = IHypervisor(_getStrategyBaseStorage()._underlying);
        //slither-disable-next-line unused-return
        (, int24 tick,,,,,) = IUniswapV3Pool(pool_).slot0();
        uint160 sqrtPrice = UniswapV3MathLib.getSqrtRatioAtTick(tick);
        uint price = UniswapV3MathLib.mulDiv(uint(sqrtPrice) * uint(sqrtPrice), _PRECISION, 2 ** (96 * 2));
        (uint pool0, uint pool1) = hypervisor.getTotalAmounts();
        //slither-disable-next-line divide-before-multiply
        uint pool0PricedInToken1 = pool0 * price / _PRECISION;
        //slither-disable-next-line divide-before-multiply
        return 1e18 * pool0PricedInToken1 / (pool0PricedInToken1 + pool1);
    }

    function _getStorage() private pure returns (GammaUniswapV3FarmStrategyStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := GAMMA_UNISWAPV3_MERKL_FARM_STRATEGY_STORAGE_LOCATION
        }
    }
}
