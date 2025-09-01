// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {LPStrategyBase, StrategyBase, IERC165, ILPStrategy} from "./base/LPStrategyBase.sol";
import {
    FarmingStrategyBase,
    StrategyLib,
    IControllable,
    IPlatform,
    IFarmingStrategy,
    IStrategy,
    IFactory
} from "./base/FarmingStrategyBase.sol";
import {MerklStrategyBase} from "./base/MerklStrategyBase.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {FarmMechanicsLib} from "./libs/FarmMechanicsLib.sol";
import {ISFLib} from "./libs/ISFLib.sol";
import {ICAmmAdapter, IAmmAdapter} from "../interfaces/ICAmmAdapter.sol";
import {VaultTypeLib} from "../core/libs/VaultTypeLib.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {AmmAdapterIdLib} from "../adapters/libs/AmmAdapterIdLib.sol";
import {IICHIVaultV4} from "../integrations/ichi/IICHIVaultV4.sol";
import {IGaugeV2_CL} from "../integrations/swapx/IGaugeV2_CL.sol";
import {IVoterV3} from "../integrations/swapx/IVoterV3.sol";
import {IAlgebraPool} from "../integrations/algebrav4/IAlgebraPool.sol";

/// @title Earn SwapX farm rewards by Ichi ALM
/// Changelog:
///   1.3.3: StrategyBase 2.5.1
///   1.3.2: Add maxDeploy, use StrategyBase 2.5.0 - #330
///   1.3.1: Refactoring to reduce contract size - #326
///   1.3.0: Use StrategyBase 2.3.0 - add fuseMode
///   1.2.0: add MerklStrategyBase, update _claimRevenue to earn SwapX gems, decrease code size
///   1.1.1: FarmingStrategyBase 1.3.3
/// @author Alien Deployer (https://github.com/a17)
contract IchiSwapXFarmStrategy is LPStrategyBase, FarmingStrategyBase, MerklStrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.3.3";

    uint internal constant PRECISION = 10 ** 18;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct PreviewDepositVars {
        uint32 twapPeriod;
        uint32 auxTwapPeriod;
        uint price;
        uint twap;
        uint auxTwap;
        uint pool0;
        uint pool1;
        address pool;
        address token0;
        address token1;
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
        if (farm.addresses.length != 2 || farm.nums.length != 0 || farm.ticks.length != 0) {
            revert IFarmingStrategy.BadFarm();
        }

        __LPStrategyBase_init(
            LPStrategyBaseInitParams({
                id: StrategyIdLib.ICHI_SWAPX_FARM,
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
        IERC20(farm.addresses[0]).forceApprove(farm.addresses[1], type(uint).max);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(LPStrategyBase, FarmingStrategyBase, MerklStrategyBase)
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
        return farm.addresses[1];
    }

    /// @inheritdoc ILPStrategy
    function ammAdapterId() public pure override returns (string memory) {
        return AmmAdapterIdLib.ALGEBRA_V4;
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
        return ISFLib.initVariants(platform_, strategyLogicId(), ammAdapterId());
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
        return StrategyIdLib.ICHI_SWAPX_FARM;
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() public view returns (uint[] memory proportions) {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        IICHIVaultV4 _underlying = IICHIVaultV4(__$__._underlying);
        proportions = new uint[](2);
        if (_underlying.allowToken0()) {
            proportions[0] = 1e18;
        } else {
            proportions[1] = 1e18;
        }
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external view override returns (string memory, bool) {
        IFactory.Farm memory farm = _getFarm();
        IICHIVaultV4 _ivault = IICHIVaultV4(farm.addresses[0]);
        address allowedToken = _ivault.allowToken0() ? _ivault.token0() : _ivault.token1();
        string memory symbol = IERC20Metadata(allowedToken).symbol();
        return (symbol, false);
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();
        ILPStrategy.LPStrategyBaseStorage storage $lp = _getLPStrategyBaseStorage();
        IFactory.Farm memory farm = IFactory(IPlatform(platform()).factory()).farm($f.farmId);
        return ISFLib.generateDescription(farm, $lp.ammAdapter);
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x965fff), bytes3(0x000000)));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        return ISFLib._assetsAmounts(_getStrategyBaseStorage());
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax)
        internal
        view
        override(StrategyBase, LPStrategyBase)
        returns (uint[] memory amountsConsumed, uint value)
    {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        IICHIVaultV4 _underlying = IICHIVaultV4(__$__._underlying);
        amountsConsumed = new uint[](2);
        if (_underlying.allowToken0()) {
            amountsConsumed[0] = amountsMax[0];
        } else {
            amountsConsumed[1] = amountsMax[1];
        }

        PreviewDepositVars memory v;
        v.pool = _underlying.pool();
        v.token0 = _underlying.token0();
        v.token1 = _underlying.token1();

        v.twapPeriod = _underlying.twapPeriod();

        // Get spot price
        v.price = _fetchSpot(_underlying.token0(), _underlying.token1(), _underlying.currentTick(), PRECISION);

        // Get TWAP price
        v.twap = _fetchTwap(v.pool, v.token0, v.token1, v.twapPeriod, PRECISION);

        v.auxTwapPeriod = _underlying.auxTwapPeriod();

        v.auxTwap = v.auxTwapPeriod > 0 ? _fetchTwap(v.pool, v.token0, v.token1, v.auxTwapPeriod, PRECISION) : v.twap;

        (uint pool0, uint pool1) = _underlying.getTotalAmounts();

        // Calculate share value in token1
        uint priceForDeposit = _getConservativePrice(v.price, v.twap, v.auxTwap, false, v.auxTwapPeriod);
        uint deposit0PricedInToken1 = amountsConsumed[0] * priceForDeposit / PRECISION;

        value = amountsConsumed[1] + deposit0PricedInToken1;
        uint totalSupply = _underlying.totalSupply();
        if (totalSupply != 0) {
            uint priceForPool = _getConservativePrice(v.price, v.twap, v.auxTwap, true, v.auxTwapPeriod);
            uint pool0PricedInToken1 = pool0 * priceForPool / PRECISION;
            value = value * totalSupply / (pool0PricedInToken1 + pool1);
        }
    }

    /// @inheritdoc StrategyBase
    function _previewDepositUnderlying(uint amount) internal view override returns (uint[] memory amountsConsumed) {
        StrategyBaseStorage storage $ = _getStrategyBaseStorage();
        IICHIVaultV4 alm = IICHIVaultV4($._underlying);
        (uint total0, uint total1) = alm.getTotalAmounts();
        uint totalInAlm = alm.totalSupply();
        amountsConsumed = new uint[](2);
        amountsConsumed[0] = total0 * amount / totalInAlm;
        amountsConsumed[1] = total1 * amount / totalInAlm;
    }

    /// @inheritdoc StrategyBase
    function _depositAssets(uint[] memory amounts, bool) internal override returns (uint value) {
        IFactory.Farm memory farm = _getFarm();
        value = IICHIVaultV4(farm.addresses[0]).deposit(amounts[0], amounts[1], address(this));
        IGaugeV2_CL(farm.addresses[1]).deposit(value);
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        $base.total += value;
    }

    /// @inheritdoc StrategyBase
    function _depositUnderlying(uint amount) internal override returns (uint[] memory amountsConsumed) {
        IFactory.Farm memory farm = _getFarm();
        IGaugeV2_CL(farm.addresses[1]).deposit(amount);
        amountsConsumed = _previewDepositUnderlying(amount);
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        $base.total += amount;
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        IFactory.Farm memory farm = _getFarm();
        IGaugeV2_CL(farm.addresses[1]).withdraw(value);
        amountsOut = new uint[](2);
        (amountsOut[0], amountsOut[1]) = IICHIVaultV4(farm.addresses[0]).withdraw(value, receiver);
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        $base.total -= value;
    }

    /// @inheritdoc StrategyBase
    function _withdrawUnderlying(uint amount, address receiver) internal override {
        IFactory.Farm memory farm = _getFarm();
        IGaugeV2_CL(farm.addresses[1]).withdraw(amount);
        IERC20(farm.addresses[0]).safeTransfer(receiver, amount);
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        $base.total -= amount;
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
        uint len = __rewardAssets.length;
        uint swpxBalancesBefore = StrategyLib.balance(__rewardAssets[0]);
        __rewardAmounts = new uint[](len);
        IFactory.Farm memory farm = _getFarm();
        IVoterV3 voter = IVoterV3(IGaugeV2_CL(farm.addresses[1]).DISTRIBUTION());
        address[] memory gauges = new address[](1);
        gauges[0] = farm.addresses[1];
        voter.claimRewards(gauges);
        __rewardAmounts[0] = StrategyLib.balance(__rewardAssets[0]) - swpxBalancesBefore;
        // other are merkl rewards
        for (uint i = 1; i < len; ++i) {
            __rewardAmounts[i] = StrategyLib.balance(__rewardAssets[i]);
        }
    }

    /// @inheritdoc StrategyBase
    function _compound() internal override {
        uint[] memory proportions = getAssetsProportions();
        uint[] memory amountsToDeposit = _swapForDepositProportion(proportions[0]);
        // nosemgrep
        if (amountsToDeposit[0] > 1 || amountsToDeposit[1] > 1) {
            uint valueToReceive;
            (amountsToDeposit, valueToReceive) = _previewDepositAssets(amountsToDeposit);
            if (valueToReceive > 10) {
                _depositAssets(amountsToDeposit, false);
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice returns equivalent _tokenOut for _amountIn, _tokenIn using spot price
     *  @param _tokenIn token the input amount is in
     *  @param _tokenOut token for the output amount
     *  @param _tick tick for the spot price
     *  @param _amountIn amount in _tokenIn
     *  @return amountOut equivalent anount in _tokenOut
     */
    function _fetchSpot(
        address _tokenIn,
        address _tokenOut,
        int24 _tick,
        uint _amountIn
    ) internal pure returns (uint amountOut) {
        return ISFLib.getQuoteAtTick(_tick, SafeCast.toUint128(_amountIn), _tokenIn, _tokenOut);
    }

    /**
     * @notice returns equivalent _tokenOut for _amountIn, _tokenIn using TWAP price
     *  @param _pool Uniswap V3 pool address to be used for price checking
     *  @param _tokenIn token the input amount is in
     *  @param _tokenOut token for the output amount
     *  @param _twapPeriod the averaging time period
     *  @param _amountIn amount in _tokenIn
     *  @return amountOut equivalent anount in _tokenOut
     */
    function _fetchTwap(
        address _pool,
        address _tokenIn,
        address _tokenOut,
        uint32 _twapPeriod,
        uint _amountIn
    ) internal view returns (uint amountOut) {
        // Leave twapTick as a int256 to avoid solidity casting
        address basePlugin = _getBasePluginFromPool(_pool);

        int twapTick = ISFLib.consult(basePlugin, _twapPeriod);
        return ISFLib.getQuoteAtTick(
            int24(twapTick), // can assume safe being result from consult()
            SafeCast.toUint128(_amountIn),
            _tokenIn,
            _tokenOut
        );
    }

    function _getBasePluginFromPool(address pool_) private view returns (address basePlugin) {
        basePlugin = IAlgebraPool(pool_).plugin();
        // make sure the base plugin is connected to the pool
        require(ISFLib.isOracleConnectedToPool(basePlugin, pool_), "IV: diconnected plugin");
    }

    /**
     * @notice Helper function to get the most conservative price
     *  @param spot Current spot price
     *  @param twap TWAP price
     *  @param auxTwap Auxiliary TWAP price
     *  @param isPool Flag indicating if the valuation is for the pool or deposit
     *  @return price Most conservative price
     */
    function _getConservativePrice(
        uint spot,
        uint twap,
        uint auxTwap,
        bool isPool,
        uint32 auxTwapPeriod
    ) internal pure returns (uint) {
        if (isPool) {
            // For pool valuation, use highest price to be conservative
            if (auxTwapPeriod > 0) {
                return Math.max(Math.max(spot, twap), auxTwap);
            }
            return Math.max(spot, twap);
        } else {
            // For deposit valuation, use lowest price to be conservative
            if (auxTwapPeriod > 0) {
                return Math.min(Math.min(spot, twap), auxTwap);
            }
            return Math.min(spot, twap);
        }
    }
}
