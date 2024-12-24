// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./base/LPStrategyBase.sol";
import "./base/FarmingStrategyBase.sol";
import "./libs/StrategyIdLib.sol";
import "./libs/FarmMechanicsLib.sol";
import "../adapters/libs/AmmAdapterIdLib.sol";
import "../integrations/convex/IConvexRewardPool.sol";
import "../integrations/convex/IBooster.sol";
import "../integrations/curve/IStableSwapViews.sol";
import "../integrations/curve/IStableSwapNG.sol";
import "../integrations/curve/IStableSwapNGPool.sol";

/// @title Staking Curve LP to Convex
/// @author Alien Deployer (https://github.com/a17)
contract CurveConvexFarmStrategy is LPStrategyBase, FarmingStrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.2.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.CurveConvexFarmStrategy")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant CURVE_CONVEX_FARM_STRATEGY_STORAGE_LOCATION =
        0xf917fd8a7d9383d2ce3ff9f03f2a847cf9d0cc44029bc864d5860ca5dfa20300;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.CurveConvexFarmStrategy
    struct CurveConvexFarmStrategyStorage {
        address booster;
        address rewardPool;
        uint pid;
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
        CurveConvexFarmStrategyStorage storage $ = _getCurveConvexFarmStorage();
        $.booster = IConvexRewardPool(farm.addresses[0]).convexBooster();
        $.rewardPool = farm.addresses[0];
        $.pid = IConvexRewardPool(farm.addresses[0]).convexPoolId();

        __LPStrategyBase_init(
            LPStrategyBaseInitParams({
                id: StrategyIdLib.CURVE_CONVEX_FARM,
                platform: addresses[0],
                vault: addresses[1],
                pool: farm.pool,
                underlying: farm.pool
            })
        );

        __FarmingStrategyBase_init(addresses[0], nums[0]);

        address[] memory _assets = assets();
        uint len = _assets.length;
        for (uint i; i < len; ++i) {
            IERC20(_assets[i]).forceApprove(farm.pool, type(uint).max);
        }

        IERC20(farm.pool).forceApprove($.booster, type(uint).max);
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
        CurveConvexFarmStrategyStorage storage $ = _getCurveConvexFarmStorage();
        return $.booster;
    }

    /// @inheritdoc ILPStrategy
    function ammAdapterId() public pure override returns (string memory) {
        return AmmAdapterIdLib.CURVE;
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
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.CURVE_CONVEX_FARM;
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

    /// @inheritdoc IStrategy
    function isHardWorkOnDepositAllowed() external pure returns (bool allowed) {
        allowed = true;
    }

    /// @inheritdoc IStrategy
    function isReadyForHardWork() external pure returns (bool) {
        return true;
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

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _depositAssets(uint[] memory amounts, bool) internal override returns (uint value) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        CurveConvexFarmStrategyStorage storage $ = _getCurveConvexFarmStorage();
        value = IStableSwapNGPool($base._underlying).add_liquidity(amounts, 0, address(this));
        $base.total += value;
        //slither-disable-next-line unused-return
        IBooster($.booster).deposit($.pid, value);
    }

    /// @inheritdoc StrategyBase
    function _depositUnderlying(uint amount) internal override returns (uint[] memory amountsConsumed) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        $base.total += amount;
        CurveConvexFarmStrategyStorage storage $ = _getCurveConvexFarmStorage();
        //slither-disable-next-line unused-return
        IBooster($.booster).deposit($.pid, amount);
        address _pool = $base._underlying;
        amountsConsumed = IStableSwapNG(_pool).get_balances();
        uint totalLp = IStableSwapNG(_pool).totalSupply();
        uint len = amountsConsumed.length;
        for (uint i; i < len; ++i) {
            amountsConsumed[i] = amount * amountsConsumed[i] / totalLp;
        }
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        CurveConvexFarmStrategyStorage storage $ = _getCurveConvexFarmStorage();
        //slither-disable-next-line unused-return
        IConvexRewardPool($.rewardPool).withdraw(value, false);
        amountsOut = IStableSwapNGPool($base._underlying).remove_liquidity(value, new uint[](assets().length), receiver);
        $base.total -= value;
    }

    /// @inheritdoc StrategyBase
    function _withdrawUnderlying(uint amount, address receiver) internal override {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        CurveConvexFarmStrategyStorage storage $ = _getCurveConvexFarmStorage();
        $base.total -= amount;
        //slither-disable-next-line unused-return
        IConvexRewardPool($.rewardPool).withdraw(amount, false);
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
        CurveConvexFarmStrategyStorage storage $ = _getCurveConvexFarmStorage();
        __rewardAssets = $f._rewardAssets;
        uint rwLen = __rewardAssets.length;
        uint[] memory balanceBefore = new uint[](rwLen);
        __rewardAmounts = new uint[](rwLen);
        for (uint i; i < rwLen; ++i) {
            balanceBefore[i] = StrategyLib.balance(__rewardAssets[i]);
        }
        IConvexRewardPool($.rewardPool).getReward(address(this));
        for (uint i; i < rwLen; ++i) {
            __rewardAmounts[i] = StrategyLib.balance(__rewardAssets[i]) - balanceBefore[i];
        }
    }

    /// @inheritdoc StrategyBase
    function _compound() internal override {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        CurveConvexFarmStrategyStorage storage $ = _getCurveConvexFarmStorage();
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
            uint value = IStableSwapNGPool($base._underlying).add_liquidity(amounts, 0, address(this));
            $base.total += value;
            //slither-disable-next-line unused-return
            IBooster($.booster).deposit($.pid, value);
        }
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax)
        internal
        view
        override(StrategyBase, LPStrategyBase)
        returns (uint[] memory amountsConsumed, uint value)
    {
        amountsConsumed = amountsMax;
        ILPStrategy.LPStrategyBaseStorage storage $lp = _getLPStrategyBaseStorage();
        value = IStableSwapViews($lp.pool).calc_token_amount(amountsMax, true);
    }

    /// @inheritdoc StrategyBase
    function _previewDepositUnderlying(uint amount) internal view override returns (uint[] memory amountsConsumed) {
        address _pool = pool();
        amountsConsumed = IStableSwapNG(_pool).get_balances();
        uint totalLp = IStableSwapNG(_pool).totalSupply();
        uint len = amountsConsumed.length;
        for (uint i; i < len; ++i) {
            amountsConsumed[i] = amount * amountsConsumed[i] / totalLp;
        }
    }

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        address _pool = pool();
        assets_ = assets();
        amounts_ = IStableSwapNG(_pool).get_balances();
        uint totalLp = IStableSwapNG(_pool).totalSupply();
        uint value = total();
        uint len = assets_.length;
        for (uint i; i < len; ++i) {
            amounts_[i] = value * amounts_[i] / totalLp;
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _generateDescription(
        IFactory.Farm memory farm,
        IAmmAdapter _ammAdapter
    ) internal view returns (string memory) {
        //slither-disable-next-line calls-loop
        return string.concat(
            "Earn ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(farm.rewardAssets), ", "),
            " on Convex by ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(_ammAdapter.poolTokens(farm.pool)), "-"),
            " Curve LP"
        );
    }

    function _getCurveConvexFarmStorage() internal pure returns (CurveConvexFarmStrategyStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := CURVE_CONVEX_FARM_STRATEGY_STORAGE_LOCATION
        }
    }
}
