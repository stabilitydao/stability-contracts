// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {LPStrategyBase, ILPStrategy} from "./base/LPStrategyBase.sol";
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
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {FarmMechanicsLib} from "./libs/FarmMechanicsLib.sol";
import {UniswapV3MathLib} from "./libs/UniswapV3MathLib.sol";
import {ALMPositionNameLib} from "./libs/ALMPositionNameLib.sol";
import {IICHIVaultGateway} from "../integrations/ichi/IICHIVaultGateway.sol";
import {IUniswapV3Pool} from "../integrations/uniswapv3/IUniswapV3Pool.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {VaultTypeLib} from "../core/libs/VaultTypeLib.sol";
import {AmmAdapterIdLib} from "../adapters/libs/AmmAdapterIdLib.sol";
import {IGaugeEquivalent} from "../integrations/equalizer/IGaugeEquivalent.sol";
import {IAmmAdapter} from "../interfaces/IAmmAdapter.sol";
import {ICAmmAdapter} from "../interfaces/ICAmmAdapter.sol";
import {ISFLib} from "./libs/ISFLib.sol";
import {IAlgebraPool} from "../integrations/algebrav4/IAlgebraPool.sol";
import {IICHIVaultV4} from "../integrations/ichi/IICHIVaultV4.sol";
// import "forge-std/console.sol";

/// @title Earn Equalizer farm rewards by Ichi ALM
/// @author Jude (https://github.com/iammrjude)
contract IchiEqualizerFarmStrategy is LPStrategyBase, FarmingStrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    uint internal constant PRECISION = 1e18;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function initialize(address[] memory addresses, uint[] memory nums, int24[] memory ticks) public initializer {
        if (addresses.length != 2 || nums.length != 1 || ticks.length != 0) {
            revert IControllable.IncorrectInitParams();
        }

        IFactory.Farm memory farm = _getFarm(addresses[0], nums[0]);
        if (farm.addresses.length != 6 || farm.nums.length != 0 || farm.ticks.length != 0) {
            revert IFarmingStrategy.BadFarm();
        }

        __LPStrategyBase_init(
            LPStrategyBaseInitParams({
                id: StrategyIdLib.ICHI_EQUALIZER_FARM,
                platform: addresses[0],
                vault: addresses[1],
                pool: farm.pool,
                underlying: farm.addresses[3]
            })
        );

        __FarmingStrategyBase_init(addresses[0], nums[0]);

        address[] memory _assets = assets();
        IERC20(_assets[0]).forceApprove(farm.addresses[0], type(uint).max);
        IERC20(_assets[1]).forceApprove(farm.addresses[0], type(uint).max);
        IERC20(farm.addresses[3]).forceApprove(farm.addresses[5], type(uint).max);
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
        return farm.addresses[5];
    }

    /// @inheritdoc ILPStrategy
    function ammAdapterId() public pure override returns (string memory) {
        return AmmAdapterIdLib.UNISWAPV3;
    }

    /// @inheritdoc IStrategy
    function getRevenue() external pure returns (address[] memory __assets, uint[] memory amounts) {}

    /// @inheritdoc IStrategy
    function initVariants(address platform_)
        public
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        ICAmmAdapter _ammAdapter = ICAmmAdapter(IPlatform(platform_).ammAdapter(keccak256(bytes(ammAdapterId()))).proxy);
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
        return total() != 0; // TODO: maybe I shoould use this
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
        return StrategyIdLib.ICHI_EQUALIZER_FARM;
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() public view returns (uint[] memory proportions) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        IICHIVaultV4 _underlying = IICHIVaultV4($base._underlying);
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
        IICHIVaultV4 _ivault = IICHIVaultV4(farm.addresses[3]);
        address allowedToken = _ivault.allowToken0() ? _ivault.token0() : _ivault.token1();
        string memory symbol = IERC20Metadata(allowedToken).symbol();
        return (symbol, false);
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();
        ILPStrategy.LPStrategyBaseStorage storage $lp = _getLPStrategyBaseStorage();
        IFactory.Farm memory farm = IFactory(IPlatform(platform()).factory()).farm($f.farmId);
        return _generateDescription(farm, $lp.ammAdapter);
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
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        assets_ = $base._assets;
        uint value = $base.total;
        IICHIVaultV4 _underlying = IICHIVaultV4($base._underlying);
        (uint amount0, uint amount1) = _underlying.getTotalAmounts();
        uint totalSupply = _underlying.totalSupply();
        amounts_ = new uint[](2);
        amounts_[0] = amount0 * value / totalSupply;
        amounts_[1] = amount1 * value / totalSupply;
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax)
        internal
        view
        override(StrategyBase, LPStrategyBase)
        returns (uint[] memory amountsConsumed, uint value)
    {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        IICHIVaultV4 _underlying = IICHIVaultV4($base._underlying);
        amountsConsumed = new uint[](2);

        if (_underlying.allowToken0()) {
            amountsConsumed[0] = amountsMax[0];
        } else {
            amountsConsumed[1] = amountsMax[1];
        }

        uint32 twapPeriod = 600;
        uint price = _fetchSpot(_underlying.token0(), _underlying.token1(), _underlying.currentTick(), PRECISION);
        uint twap = _fetchTwap(_underlying.pool(), _underlying.token0(), _underlying.token1(), twapPeriod, PRECISION);
        (uint pool0, uint pool1) = _underlying.getTotalAmounts();
        // aggregated deposit
        uint deposit0PricedInToken1 = (amountsConsumed[0] * ((price < twap) ? price : twap)) / PRECISION;

        value = amountsConsumed[1] + deposit0PricedInToken1;
        uint totalSupply = _underlying.totalSupply();
        if (totalSupply != 0) {
            uint pool0PricedInToken1 = (pool0 * ((price > twap) ? price : twap)) / PRECISION;
            value = value * totalSupply / (pool0PricedInToken1 + pool1);
        }
    }

    /// @inheritdoc StrategyBase
    function _previewDepositUnderlying(uint amount) internal view override returns (uint[] memory amountsConsumed) {
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        IICHIVaultV4 alm = IICHIVaultV4($base._underlying);
        (uint total0, uint total1) = alm.getTotalAmounts();
        uint totalInAlm = alm.totalSupply();
        amountsConsumed = new uint[](2);
        amountsConsumed[0] = amount * total0 / totalInAlm;
        amountsConsumed[1] = amount * total1 / totalInAlm;
    }

    /// @inheritdoc StrategyBase
    function _depositAssets(uint[] memory amounts, bool claimRevenue) internal override returns (uint value) {
        FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        IFactory.Farm memory farm = _getFarm();
        if (claimRevenue) {
            (,,, uint[] memory rewardAmounts) = _claimRevenue();
            uint len = rewardAmounts.length;
            // nosemgrep
            for (uint i; i < len; ++i) {
                // nosemgrep
                $f._rewardsOnBalance[i] += rewardAmounts[i];
            }
        }
        uint initialValue = IERC20(farm.addresses[3]).balanceOf(address(this));
        uint minimumProceeds = 1;
        // TODO: How do I know what is `amounts[0]` if it is the right deposit amount?
        // Note: It deposits only token0
        // console.logUint(amounts[0]);
        IICHIVaultGateway(farm.addresses[0]).forwardDepositToICHIVault(
            farm.addresses[3], farm.addresses[4], farm.addresses[1], amounts[0], minimumProceeds, address(this)
        );
        value = IERC20(farm.addresses[3]).balanceOf(address(this)) - initialValue;
        IGaugeEquivalent(farm.addresses[5]).deposit(value);
        $base.total += value;
    }

    /// @inheritdoc StrategyBase
    function _depositUnderlying(uint amount) internal override returns (uint[] memory amountsConsumed) {
        IFactory.Farm memory farm = _getFarm();
        IGaugeEquivalent(farm.addresses[5]).deposit(amount);
        amountsConsumed = _previewDepositUnderlying(amount);
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        $base.total += amount;
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        IFactory.Farm memory farm = _getFarm();
        IGaugeEquivalent(farm.addresses[5]).withdraw(value);
        amountsOut = new uint[](2);
        (amountsOut[0], amountsOut[1]) = IICHIVaultV4(farm.addresses[3]).withdraw(value, receiver);
        StrategyBaseStorage storage $base = _getStrategyBaseStorage();
        $base.total -= value;
    }

    /// @inheritdoc StrategyBase
    function _withdrawUnderlying(uint amount, address receiver) internal override {
        IFactory.Farm memory farm = _getFarm();
        IGaugeEquivalent(farm.addresses[5]).withdraw(amount);
        IERC20(farm.addresses[3]).safeTransfer(receiver, amount);
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
        uint rwLen = __rewardAssets.length;
        uint[] memory balanceBefore = new uint[](rwLen);
        __rewardAmounts = new uint[](rwLen);
        for (uint i; i < rwLen; ++i) {
            balanceBefore[i] = StrategyLib.balance(__rewardAssets[i]);
        }
        IFactory.Farm memory farm = _getFarm();
        IGaugeEquivalent(farm.addresses[5]).getReward(address(this), __rewardAssets);
        for (uint i; i < rwLen; ++i) {
            __rewardAmounts[i] = StrategyLib.balance(__rewardAssets[i]) - balanceBefore[i];
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
        basePlugin = IAlgebraPool(pool_).plugin(); // TODO: Shouldn't it be Uniswap Pool ?
        // make sure the base plugin is connected to the pool
        require(ISFLib.isOracleConnectedToPool(basePlugin, pool_), "IV: diconnected plugin");
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
            " on Equalizer by ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(_ammAdapter.poolTokens(farm.pool)), "-"),
            " Ichi ",
            //slither-disable-next-line calls-loop
            IERC20Metadata(farm.addresses[3]).symbol()
        );
    }
}
