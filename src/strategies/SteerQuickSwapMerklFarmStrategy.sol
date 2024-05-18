// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./base/LPStrategyBase.sol";
import "./base/FarmingStrategyBase.sol";
import "./libs/DQMFLib.sol";
import "./libs/StrategyIdLib.sol";
import "./libs/FarmMechanicsLib.sol";
import "./libs/ALMPositionNameLib.sol";
import "./libs/UniswapV3MathLib.sol";
import "../adapters/libs/AmmAdapterIdLib.sol";
import "../interfaces/ICAmmAdapter.sol";
import "../integrations/chainlink/IFeedRegistryInterface.sol";
import "../integrations/algebra/IAlgebraPool.sol";
import "../integrations/steer/IMultiPositionManager.sol";
import "../integrations/steer/IMultiPositionManagerFactory.sol";
import "forge-std/console.sol";

/// @title Earning MERKL rewards by DeFiEdge strategy on QuickSwapV3
/// @author Only Forward (https://github.com/OnlyForward0613)
contract SteerQuickSwapMerklFarmStrategy is LPStrategyBase, FarmingStrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    uint internal constant _PRECISION = 1e36;

    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    address internal constant USD = address(840);
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
            LPStrategyBaseInitParams({
                id: StrategyIdLib.STEER_QUICKSWAP_MERKL_FARM,
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
        return StrategyIdLib.STEER_QUICKSWAP_MERKL_FARM;
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
    function getSpecificName() external pure override returns (string memory, bool) {
        // IFactory.Farm memory farm = _getFarm();
        // string memory shortAddr = DQMFLib.shortAddress(farm.addresses[0]);
        // return (string.concat(ALMPositionNameLib.getName(farm.nums[0]), " ", shortAddr), true);
        return ("ok-steer", true);
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();
        ILPStrategy.LPStrategyBaseStorage storage $lp = _getLPStrategyBaseStorage();
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
        // StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        // (,, value) = IMultiPositionManager(__$__._underlying).deposit(amounts[0], amounts[1], 0, 0, address(this));
        // __$__.total += value;
    }

    /// @inheritdoc StrategyBase
    // function _depositUnderlying(uint amount) internal override returns (uint[] memory amountsConsumed) {
    //     StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
    //     amountsConsumed = _previewDepositUnderlying(amount);
    //     __$__.total += amount;
    // }

    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        // StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        // __$__.total -= value;
        // amountsOut = new uint[](2);
        // (amountsOut[0], amountsOut[1]) = IMultiPositionManager(__$__._underlying).withdraw(value, 0, 0, receiver);
        // if (receiver != address(this)) {
        //     address[] memory _assets = __$__._assets;
        //     IERC20(_assets[0]).safeTransfer(receiver, amountsOut[0]);
        //     IERC20(_assets[1]).safeTransfer(receiver, amountsOut[1]);
        // }
    }

    /// @inheritdoc StrategyBase
    function _withdrawUnderlying(uint amount, address receiver) internal override {
        // StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        // IERC20(__$__._underlying).safeTransfer(receiver, amount);
        // __$__.total -= amount;
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
        // StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        // FarmingStrategyBaseStorage storage _$_ = _getFarmingStrategyBaseStorage();
        // __assets = __$__._assets;
        // __rewardAssets = _$_._rewardAssets;
        // __amounts = new uint[](2);
        // uint rwLen = __rewardAssets.length;
        // __rewardAmounts = new uint[](rwLen);
        // for (uint i; i < rwLen; ++i) {
        //     __rewardAmounts[i] = StrategyLib.balance(__rewardAssets[i]);
        // }
    }

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        // StrategyBaseStorage storage $ = _getStrategyBaseStorage();
        // assets_ = $._assets;
        // amounts_ = new uint[](2);
        // uint _total = $.total;
        // if (_total > 0) {
        //     IMultiPositionManager multiPositionManager = IMultiPositionManager($._underlying);
        //     (amounts_[0], amounts_[1]) = multiPositionManager.getTotalAmounts();
        //     uint totalInMultiPositionManager = multiPositionManager.totalSupply();
        //     (amounts_[0], amounts_[1]) =
        //         (amounts_[0] * _total / totalInMultiPositionManager, amounts_[1] * _total / totalInMultiPositionManager);
        // }
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
        IMultiPositionManager _underlying = IMultiPositionManager(__$__._underlying);
        IMultiPositionManager.LiquidityPositions memory ticks_;
        (ticks_.lowerTick, ticks_.upperTick, )  = _underlying.getPositions();
        int24[] memory ticks = new int24[](2);
        ticks[0] = ticks_.lowerTick[0];
        ticks[1] = ticks_.upperTick[0];
        (, amountsConsumed) = ICAmmAdapter(address(ammAdapter())).getLiquidityForAmounts(pool(), amountsMax, ticks);

        uint[] memory totalAmounts = new uint[](2);
        (totalAmounts[0], totalAmounts[1]) = _underlying.getTotalAmounts();
        IFeedRegistryInterface chainlinkRegistry = IFeedRegistryInterface(_underlying.vaultRegistry());
        bool[2] memory usdAsBase;
        usdAsBase[0] = false;
        usdAsBase[1] = false;
        value = _calculateShares(
            chainlinkRegistry,
            ammAdapter().poolTokens(pool()),
            usdAsBase,
            amountsConsumed[0],
            amountsConsumed[1],
            totalAmounts[0],
            totalAmounts[1],
            _underlying.maxTotalSupply()
        );
    }
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // function _getUnderlyingAssetsAmounts() internal view returns (uint[] memory amounts_) {
    //     StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
    //     IMultiPositionManager _underlying = IMultiPositionManager(__$__._underlying);
    //     IAlgebraPool _pool = IAlgebraPool(pool());
    //     ICAmmAdapter _adapter = ICAmmAdapter(address(ammAdapter()));
    //     amounts_ = new uint[](2);

    //     amounts_[0] = _underlying.reserve0();
    //     amounts_[1] = _underlying.reserve1();

    //     // assets amounts without claimed fees..
    //     IMultiPositionManager.LiquidityPositions memory ticks;
    //     (ticks.lowerTick, ticks.upperTick, )  = _underlying.getPositions();
    //     uint len = ticks.lowerTick.length;
    //     for (uint i; i < len; ++i) {
    //         (uint128 currentLiquidity,,,,,) =
    //             _pool.positions(_computePositionKey(address(_underlying), ticks.lowerTick[i], ticks.upperTick[i]));
    //         if (currentLiquidity > 0) {
    //             int24[] memory _ticks = new int24[](2);
    //             _ticks[0] = ticks.lowerTick[i];
    //             _ticks[1] = ticks.upperTick[i];
    //             uint[] memory amounts = _adapter.getAmountsForLiquidity(address(_pool), _ticks, currentLiquidity);
    //             amounts_[0] += amounts[0];
    //             amounts_[1] += amounts[1];
    //         }
    //     }
    // }
    /// @dev proportion of 1e18
    function _getProportion0(address pool_) internal view returns (uint) {
        IMultiPositionManager hypervisor = IMultiPositionManager(_getStrategyBaseStorage()._underlying);
        //slither-disable-next-line unused-return
        (, int24 tick,,,,,) = IAlgebraPool(pool_).globalState();
        uint160 sqrtPrice = UniswapV3MathLib.getSqrtRatioAtTick(tick);
        uint price = UniswapV3MathLib.mulDiv(uint(sqrtPrice) * uint(sqrtPrice), _PRECISION, 2 ** (96 * 2));
        (uint pool0, uint pool1) = hypervisor.getTotalAmounts();
        //slither-disable-next-line divide-before-multiply
        uint pool0PricedInToken1 = pool0 * price / _PRECISION;
        //slither-disable-next-line divide-before-multiply
        return 1e18 * pool0PricedInToken1 / (pool0PricedInToken1 + pool1);
    }

    /// @dev Calculates the shares to be given for specific position for Steer strategy
    /// @param _registry Chainlink registry interface
    /// @param _poolTokens Algebra pool tokens
    /// @param _isBase Is USD used as base
    /// @param _amount0 Amount of token0
    /// @param _amount1 Amount of token1
    /// @param _totalAmount0 Total amount of token0
    /// @param _totalAmount1 Total amount of token1
    /// @param _totalShares Total Number of shares
    function _calculateShares(
        IFeedRegistryInterface _registry,
        address[] memory _poolTokens,
        bool[2] memory _isBase,
        uint _amount0,
        uint _amount1,
        uint _totalAmount0,
        uint _totalAmount1,
        uint _totalShares
    ) internal view returns (uint share) {
        uint __amount0 = _normalise(_poolTokens[0], _amount0);
        uint __amount1 = _normalise(_poolTokens[1], _amount1);
        _totalAmount0 = _normalise(_poolTokens[0], _totalAmount0);
        _totalAmount1 = _normalise(_poolTokens[1], _totalAmount1);
        uint token0Price = _getPriceInUSD(_registry, _poolTokens[0], _isBase[0]);
        uint token1Price = _getPriceInUSD(_registry, _poolTokens[1], _isBase[1]);
        // here we assume that _totalShares always > 0, because steer strategy is already inited
        uint numerator = token0Price * __amount0 + token1Price * __amount1;
        uint denominator = token0Price * _totalAmount0 + token1Price * _totalAmount1;
        share = UniswapV3MathLib.mulDiv(numerator, _totalShares, denominator);
    }

    function _computePositionKey(address owner, int24 bottomTick, int24 topTick) internal pure returns (bytes32 key) {
        assembly {
            key := or(shl(24, or(shl(24, owner), and(bottomTick, 0xFFFFFF))), and(topTick, 0xFFFFFF))
        }
    }

    function _normalise(address _token, uint _amount) internal view returns (uint normalised) {
        normalised = _amount;
        uint _decimals = IERC20Metadata(_token).decimals();
        if (_decimals < 18) {
            uint missingDecimals = 18 - _decimals;
            normalised = _amount * 10 ** missingDecimals;
        } else if (_decimals > 18) {
            uint extraDecimals = _decimals - 18;
            normalised = _amount / 10 ** extraDecimals;
        }
    }

    /**
     * @notice Gets price in USD, if USD feed is not available use ETH feed
     * @param _registry Interface of the Chainlink registry
     * @param _token the token we want to convert into USD
     * @param _isBase if the token supports base as USD or requires conversion from ETH
     */
    function _getPriceInUSD(
        IFeedRegistryInterface _registry,
        address _token,
        bool _isBase
    ) internal view returns (uint price) {
        if (_isBase) {
            price = _getChainlinkPrice(_registry, _token, USD, 86400);
        } else {
            price = _getChainlinkPrice(_registry, _token, ETH, 86400);

            price = UniswapV3MathLib.mulDiv(
                price, _getChainlinkPrice(_registry, ETH, USD, 86400), 1e18
            );
        }
    }

    /**
     * @notice Returns latest Chainlink price, and normalise it
     * @param _registry registry
     * @param _base Base Asset
     * @param _quote Quote Asset
     */
    function _getChainlinkPrice(
        IFeedRegistryInterface _registry,
        address _base,
        address _quote,
        uint _validPeriod
    ) internal view returns (uint price) {
        (, int _price,, uint updatedAt,) = _registry.latestRoundData(_base, _quote);

        require(block.timestamp - updatedAt < _validPeriod, "OLD_PRICE");

        if (_price <= 0) {
            return 0;
        }

        // normalise the price to 18 decimals
        uint _decimals = _registry.decimals(_base, _quote);

        if (_decimals < 18) {
            uint missingDecimals = 18 - _decimals;
            price = uint(_price) * 10 ** missingDecimals;
        } else if (_decimals > 18) {
            uint extraDecimals = _decimals - 18;
            price = uint(_price) / (10 ** extraDecimals);
        }

        return price;
    }
}
