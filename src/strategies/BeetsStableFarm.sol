// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {StrategyBase} from "./base/StrategyBase.sol";
import {LPStrategyBase} from "./base/LPStrategyBase.sol";
import {FarmingStrategyBase} from "./base/FarmingStrategyBase.sol";
import {StrategyLib} from "./libs/StrategyLib.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {FarmMechanicsLib} from "./libs/FarmMechanicsLib.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IAmmAdapter} from "../interfaces/IAmmAdapter.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IFarmingStrategy} from "../interfaces/IFarmingStrategy.sol";
import {ILPStrategy} from "../interfaces/ILPStrategy.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {VaultTypeLib} from "../core/libs/VaultTypeLib.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {AmmAdapterIdLib} from "../adapters/libs/AmmAdapterIdLib.sol";
import {IBalancerAdapter} from "../interfaces/IBalancerAdapter.sol";
import {IBVault} from "../integrations/balancer/IBVault.sol";
import {IBComposableStablePoolMinimal} from "../integrations/balancer/IBComposableStablePoolMinimal.sol";
import {IBalancerGauge} from "../integrations/balancer/IBalancerGauge.sol";

/// @title Earn Beets stable pool LP fees and gauge rewards
/// @author Alien Deployer (https://github.com/a17)
contract BeetsStableFarm is LPStrategyBase, FarmingStrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct BalancerMethodVars {
        bytes32 poolId;
        address[] poolTokens;
        uint bptIndex;
        uint len;
        uint[] allAmounts;
        uint[] amounts;
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
        if (farm.addresses.length != 1 || farm.nums.length != 0 || farm.ticks.length != 0) {
            revert IFarmingStrategy.BadFarm();
        }

        __LPStrategyBase_init(
            LPStrategyBaseInitParams({
                id: StrategyIdLib.BEETS_STABLE_FARM,
                platform: addresses[0],
                vault: addresses[1],
                pool: farm.pool,
                underlying: farm.pool
            })
        );

        __FarmingStrategyBase_init(addresses[0], nums[0]);

        address[] memory _assets = assets();
        uint len = _assets.length;
        address balancerVault = IBComposableStablePoolMinimal(farm.pool).getVault();
        for (uint i; i < len; ++i) {
            IERC20(_assets[i]).forceApprove(balancerVault, type(uint).max);
        }

        IERC20(farm.pool).forceApprove(farm.addresses[0], type(uint).max);
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
        return AmmAdapterIdLib.BALANCER_COMPOSABLE_STABLE;
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
        IAmmAdapter _ammAdapter = IAmmAdapter(IPlatform(platform_).ammAdapter(keccak256(bytes(ammAdapterId()))).proxy);
        addresses = new address[](0);
        ticks = new int24[](0);

        IFactory.Farm[] memory farms = IFactory(IPlatform(platform_).factory()).farms();
        uint len = farms.length;
        //slither-disable-next-line uninitialized-local
        uint localTtotal;
        //nosemgrep
        for (uint i; i < len; ++i) {
            //nosemgrep
            IFactory.Farm memory farm = farms[i];
            //nosemgrep
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, strategyLogicId())) {
                ++localTtotal;
            }
        }

        variants = new string[](localTtotal);
        nums = new uint[](localTtotal);
        localTtotal = 0;
        //nosemgrep
        for (uint i; i < len; ++i) {
            //nosemgrep
            IFactory.Farm memory farm = farms[i];
            //nosemgrep
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, strategyLogicId())) {
                nums[localTtotal] = i;
                //slither-disable-next-line calls-loop
                variants[localTtotal] = _generateDescription(farm, _ammAdapter);
                ++localTtotal;
            }
        }
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
        return FarmMechanicsLib.CLASSIC;
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
        return StrategyIdLib.BEETS_STABLE_FARM;
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() public view returns (uint[] memory proportions) {
        ILPStrategy.LPStrategyBaseStorage storage $lp = _getLPStrategyBaseStorage();
        proportions = $lp.ammAdapter.getProportions($lp.pool);
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        //slither-disable-next-line too-many-digits
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0xeeeeee), bytes3(0x000000)));
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external pure override returns (string memory, bool) {
        return ("", false);
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();
        ILPStrategy.LPStrategyBaseStorage storage $lp = _getLPStrategyBaseStorage();
        IFactory.Farm memory farm = IFactory(IPlatform(platform()).factory()).farm($f.farmId);
        return _generateDescription(farm, $lp.ammAdapter);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _depositAssets(uint[] memory amounts, bool) internal override returns (uint value) {
        ILPStrategy.LPStrategyBaseStorage storage $lp = _getLPStrategyBaseStorage();
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        IBComposableStablePoolMinimal _pool = IBComposableStablePoolMinimal($lp.pool);
        BalancerMethodVars memory v;

        v.poolId = _pool.getPoolId();
        (v.poolTokens,,) = IBVault(_pool.getVault()).getPoolTokens(v.poolId);

        value = IERC20(address(_pool)).balanceOf(address(this));

        v.bptIndex = _pool.getBptIndex();
        v.len = v.poolTokens.length;
        v.allAmounts = new uint[](v.len);
        uint k;
        for (uint i; i < v.len; ++i) {
            if (i != v.bptIndex) {
                v.allAmounts[i] = amounts[k];
                k++;
            }
        }

        IBVault(_pool.getVault()).joinPool(
            v.poolId,
            address(this),
            address(this),
            IBVault.JoinPoolRequest({
                assets: v.poolTokens,
                maxAmountsIn: v.allAmounts,
                userData: abi.encode(IBVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT, amounts, 0),
                fromInternalBalance: false
            })
        );
        value = IERC20(address(_pool)).balanceOf(address(this)) - value;
        $base.total += value;

        IFactory.Farm memory farm = _getFarm();
        IBalancerGauge(farm.addresses[0]).deposit(value);
    }

    /// @inheritdoc StrategyBase
    function _depositUnderlying(uint amount) internal override returns (uint[] memory amountsConsumed) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        $base.total += amount;
        IFactory.Farm memory farm = _getFarm();
        IBalancerGauge(farm.addresses[0]).deposit(amount);
        amountsConsumed = _calcAssetsAmounts(amount);
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        IFactory.Farm memory farm = _getFarm();
        IBComposableStablePoolMinimal _pool = IBComposableStablePoolMinimal(pool());
        BalancerMethodVars memory v;

        (v.poolTokens,,) = IBVault(_pool.getVault()).getPoolTokens(_pool.getPoolId());

        IBalancerGauge(farm.addresses[0]).withdraw(value);

        address[] memory __assets = assets();
        v.len = __assets.length;
        amountsOut = new uint[](v.len);
        for (uint i; i < v.len; ++i) {
            amountsOut[i] = IERC20(__assets[i]).balanceOf(receiver);
        }

        v.amounts = _calcAssetsAmounts(value);
        v.amounts = _extractFee(address(_pool), v.amounts);

        IBVault(_pool.getVault()).exitPool(
            _pool.getPoolId(),
            address(this),
            payable(receiver),
            IBVault.ExitPoolRequest({
                assets: v.poolTokens,
                minAmountsOut: new uint[](v.poolTokens.length),
                userData: abi.encode(1, v.amounts, value),
                toInternalBalance: false
            })
        );

        for (uint i; i < v.len; ++i) {
            amountsOut[i] = IERC20(__assets[i]).balanceOf(receiver) - amountsOut[i];
        }

        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        $base.total -= value;
    }

    /// @inheritdoc StrategyBase
    function _withdrawUnderlying(uint amount, address receiver) internal override {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        $base.total -= amount;
        IFactory.Farm memory farm = _getFarm();
        IBalancerGauge(farm.addresses[0]).withdraw(amount);
        IERC20($base._underlying).safeTransfer(receiver, amount);
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
        IBalancerGauge(farm.addresses[0]).claim_rewards();
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
        if (notZero) {
            _depositAssets(amounts, false);
        }
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory)
        internal
        pure
        override(StrategyBase, LPStrategyBase)
        returns (uint[] memory, uint)
    {
        revert("Not supported");
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssetsWrite(uint[] memory amountsMax)
        internal
        override(StrategyBase)
        returns (uint[] memory amountsConsumed, uint value)
    {
        IBalancerAdapter _ammAdapter =
            IBalancerAdapter(IPlatform(platform()).ammAdapter(keccak256(bytes(ammAdapterId()))).proxy);
        ILPStrategy.LPStrategyBaseStorage storage $lp = _getLPStrategyBaseStorage();
        (value, amountsConsumed) = _ammAdapter.getLiquidityForAmountsWrite($lp.pool, amountsMax);
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssetsWrite(
        address[] memory,
        uint[] memory amountsMax
    ) internal override(StrategyBase) returns (uint[] memory amountsConsumed, uint value) {
        return _previewDepositAssetsWrite(amountsMax);
    }

    /// @inheritdoc StrategyBase
    function _previewDepositUnderlying(uint amount) internal view override returns (uint[] memory amountsConsumed) {
        // todo
    }

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        amounts_ = _calcAssetsAmounts(total());
        assets_ = assets();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _calcAssetsAmounts(uint shares) internal view returns (uint[] memory amounts_) {
        IBComposableStablePoolMinimal _pool = IBComposableStablePoolMinimal(pool());
        uint bptIndex = _pool.getBptIndex();
        (, uint[] memory balances,) = IBVault(_pool.getVault()).getPoolTokens(_pool.getPoolId());
        uint supply = IERC20(address(_pool)).totalSupply() - balances[bptIndex];
        uint len = balances.length - 1;
        amounts_ = new uint[](len);
        for (uint i; i < len; ++i) {
            amounts_[i] = shares * balances[i < bptIndex ? i : i + 1] / supply;
        }
    }

    function _extractFee(address _pool, uint[] memory amounts_) internal view returns (uint[] memory __amounts) {
        __amounts = amounts_;
        uint len = amounts_.length;
        uint fee = IBComposableStablePoolMinimal(_pool).getSwapFeePercentage();
        for (uint i; i < len; ++i) {
            __amounts[i] -= __amounts[i] * fee / 1e18;
        }
    }

    function _generateDescription(
        IFactory.Farm memory farm,
        IAmmAdapter _ammAdapter
    ) internal view returns (string memory) {
        //slither-disable-next-line calls-loop
        return string.concat(
            "Earn ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(farm.rewardAssets), ", "),
            " and fees on Beets stable pool by ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(_ammAdapter.poolTokens(farm.pool)), "-"),
            " LP"
        );
    }
}
