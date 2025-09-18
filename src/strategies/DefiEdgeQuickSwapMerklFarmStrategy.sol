// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {LPStrategyBase} from "./base/LPStrategyBase.sol";
import {ILPStrategy} from "../../src/interfaces/ILPStrategy.sol";
import {MerklStrategyBase} from "./base/MerklStrategyBase.sol";
import {FarmingStrategyBase} from "./base/FarmingStrategyBase.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IFarmingStrategy} from "../interfaces/IFarmingStrategy.sol";
import {StrategyBase, StrategyLib} from "./base/StrategyBase.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {DQMFLib} from "./libs/DQMFLib.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {FarmMechanicsLib} from "./libs/FarmMechanicsLib.sol";
import {ALMPositionNameLib} from "./libs/ALMPositionNameLib.sol";
import {AmmAdapterIdLib} from "../adapters/libs/AmmAdapterIdLib.sol";
import {ICAmmAdapter} from "../interfaces/ICAmmAdapter.sol";
import {IAmmAdapter} from "../interfaces/IAmmAdapter.sol";
import {IDefiEdgeStrategy} from "../integrations/defiedge/IDefiEdgeStrategy.sol";
import {IDefiEdgeStrategyFactory} from "../integrations/defiedge/IDefiEdgeStrategyFactory.sol";
import {IFeedRegistryInterface} from "../integrations/chainlink/IFeedRegistryInterface.sol";
import {IAlgebraPool} from "../integrations/algebra/IAlgebraPool.sol";

/// @title Earning MERKL rewards by DeFiEdge strategy on QuickSwapV3
/// Changelog
///   1.5.2: use LPStrategyBase 1.2.0
///   1.5.1: Refactoring to reduce contract size - #326
/// @author Alien Deployer (https://github.com/a17)
contract DefiEdgeQuickSwapMerklFarmStrategy is LPStrategyBase, MerklStrategyBase, FarmingStrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.5.2";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function initialize(address[] memory addresses, uint[] memory nums, int24[] memory ticks) public initializer {
        if (addresses.length != 2 || nums.length != 1 || ticks.length != 0) {
            revert IControllable.IncorrectInitParams();
        }

        IFactory.Farm memory farm = _getFarm(addresses[0], nums[0]);
        if (farm.addresses.length != 1 || farm.nums.length != 1 || farm.ticks.length != 0) {
            revert IFarmingStrategy.BadFarm();
        }

        __LPStrategyBase_init(
            LpStrategyBaseInitParams({
                id: StrategyIdLib.DEFIEDGE_QUICKSWAP_MERKL_FARM,
                platform: addresses[0],
                vault: addresses[1],
                pool: farm.pool,
                underlying: farm.addresses[0]
            })
        );

        __FarmingStrategyBase_init(addresses[0], nums[0]);

        address[] memory _assets = assets();
        IERC20(_assets[0]).forceApprove(farm.addresses[0], type(uint).max);
        IERC20(_assets[1]).forceApprove(farm.addresses[0], type(uint).max);
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
        return AmmAdapterIdLib.ALGEBRA;
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
        IAmmAdapter _ammAdapter = IAmmAdapter(IPlatform(platform_).ammAdapter(keccak256(bytes(ammAdapterId()))).proxy);
        addresses = new address[](0);
        ticks = new int24[](0);

        IFactory.Farm[] memory farms = IFactory(IPlatform(platform_).factory()).farms();
        uint len = farms.length;
        //slither-disable-next-line uninitialized-local
        uint localTtotal;
        // nosemgrep
        for (uint i; i < len; ++i) {
            // nosemgrep
            IFactory.Farm memory farm = farms[i];
            // nosemgrep
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, strategyLogicId())) {
                ++localTtotal;
            }
        }

        variants = new string[](localTtotal);
        nums = new uint[](localTtotal);
        localTtotal = 0;
        // nosemgrep
        for (uint i; i < len; ++i) {
            // nosemgrep
            IFactory.Farm memory farm = farms[i];
            // nosemgrep
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, strategyLogicId())) {
                nums[localTtotal] = i;
                //slither-disable-next-line calls-loop
                variants[localTtotal] = DQMFLib.generateDescription(farm, _ammAdapter);
                ++localTtotal;
            }
        }
    }

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.DEFIEDGE_QUICKSWAP_MERKL_FARM;
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() external view returns (uint[] memory proportions) {
        proportions = new uint[](2);
        proportions[0] = _getProportion0(pool());
        proportions[1] = 1e18 - proportions[0];
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x3477ff), bytes3(0x000000)));
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external view override returns (string memory, bool) {
        IFactory.Farm memory farm = _getFarm();
        string memory shortAddr = DQMFLib.shortAddress(farm.addresses[0]);
        return (string.concat(ALMPositionNameLib.getName(farm.nums[0]), " ", shortAddr), true);
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();
        ILPStrategy.LpStrategyBaseStorage storage $lp = _getLPStrategyBaseStorage();
        IFactory.Farm memory farm = IFactory(IPlatform(platform()).factory()).farm($f.farmId);
        return DQMFLib.generateDescription(farm, $lp.ammAdapter);
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

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _depositAssets(uint[] memory amounts, bool /*claimRevenue*/ ) internal override returns (uint value) {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        (,, value) = IDefiEdgeStrategy(__$__._underlying).mint(amounts[0], amounts[1], 0, 0, 0);
        __$__.total += value;
    }

    /// @inheritdoc StrategyBase
    function _depositUnderlying(uint amount) internal override returns (uint[] memory amountsConsumed) {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        amountsConsumed = _previewDepositUnderlying(amount);
        __$__.total += amount;
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        __$__.total -= value;
        amountsOut = new uint[](2);
        (amountsOut[0], amountsOut[1]) = IDefiEdgeStrategy(__$__._underlying).burn(value, 0, 0);
        if (receiver != address(this)) {
            address[] memory _assets = __$__._assets;
            IERC20(_assets[0]).safeTransfer(receiver, amountsOut[0]);
            IERC20(_assets[1]).safeTransfer(receiver, amountsOut[1]);
        }
    }

    /// @inheritdoc StrategyBase
    function _withdrawUnderlying(uint amount, address receiver) internal override {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        IERC20(__$__._underlying).safeTransfer(receiver, amount);
        __$__.total -= amount;
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
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        IDefiEdgeStrategy _underlying = IDefiEdgeStrategy(__$__._underlying);
        {
            IDefiEdgeStrategy.Tick memory ticks_ = _underlying.ticks(0);
            int24[] memory ticks = _ticksToArr(ticks_);
            (, amountsConsumed) = ICAmmAdapter(address(ammAdapter())).getLiquidityForAmounts(pool(), amountsMax, ticks);
        }

        // get total amounts WITHOUT fees, its not very good, but ok..
        uint[] memory totalAmounts = _getUnderlyingAssetsAmounts();

        IDefiEdgeStrategyFactory factory = IDefiEdgeStrategyFactory(_underlying.factory());
        IFeedRegistryInterface chainlinkRegistry = IFeedRegistryInterface(factory.chainlinkRegistry());
        bool[2] memory usdAsBase;
        usdAsBase[0] = _underlying.usdAsBase(0);
        usdAsBase[1] = _underlying.usdAsBase(1);
        value = DQMFLib.calculateShares(
            factory,
            chainlinkRegistry,
            ammAdapter().poolTokens(pool()),
            usdAsBase,
            amountsConsumed[0],
            amountsConsumed[1],
            totalAmounts[0],
            totalAmounts[1],
            _underlying.totalSupply()
        );
    }

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        assets_ = __$__._assets;
        IDefiEdgeStrategy _underlying = IDefiEdgeStrategy(__$__._underlying);
        uint value = __$__.total;
        uint[] memory totalAmounts = _getUnderlyingAssetsAmounts();
        uint totalSupply = _underlying.totalSupply();
        amounts_ = new uint[](2);
        amounts_[0] = totalAmounts[0] * value / totalSupply;
        amounts_[1] = totalAmounts[1] * value / totalSupply;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getUnderlyingAssetsAmounts() internal view returns (uint[] memory amounts_) {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        IDefiEdgeStrategy _underlying = IDefiEdgeStrategy(__$__._underlying);
        IAlgebraPool _pool = IAlgebraPool(pool());
        ICAmmAdapter _adapter = ICAmmAdapter(address(ammAdapter()));
        amounts_ = new uint[](2);

        amounts_[0] = _underlying.reserve0();
        amounts_[1] = _underlying.reserve1();

        // assets amounts without claimed fees..
        IDefiEdgeStrategy.Tick[] memory ticks = _underlying.getTicks();
        uint len = ticks.length;
        for (uint i; i < len; ++i) {
            IDefiEdgeStrategy.Tick memory tick = ticks[i];
            (uint128 currentLiquidity,,,,,) =
                _pool.positions(_computePositionKey(address(_underlying), tick.tickLower, tick.tickUpper));
            if (currentLiquidity > 0) {
                int24[] memory _ticks = _ticksToArr(tick);
                uint[] memory amounts = _adapter.getAmountsForLiquidity(address(_pool), _ticks, currentLiquidity);
                amounts_[0] += amounts[0];
                amounts_[1] += amounts[1];
            }
        }
    }

    function _getProportion0(address pool_) internal view returns (uint) {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        IDefiEdgeStrategy.Tick memory ticks_ = IDefiEdgeStrategy(__$__._underlying).ticks(0);
        int24[] memory ticks = _ticksToArr(ticks_);
        return ICAmmAdapter(address(ammAdapter())).getProportions(pool_, ticks)[0];
    }

    function _computePositionKey(address owner, int24 bottomTick, int24 topTick) internal pure returns (bytes32 key) {
        assembly {
            key := or(shl(24, or(shl(24, owner), and(bottomTick, 0xFFFFFF))), and(topTick, 0xFFFFFF))
        }
    }

    function _ticksToArr(IDefiEdgeStrategy.Tick memory ticks_) internal pure returns (int24[] memory ticks) {
        ticks = new int24[](2);
        (ticks[0], ticks[1]) = (ticks_.tickLower, ticks_.tickUpper);
    }
}
