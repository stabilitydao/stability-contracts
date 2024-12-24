// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "./base/LPStrategyBase.sol";
import "./base/MerklStrategyBase.sol";
import "./base/FarmingStrategyBase.sol";
import "./libs/StrategyIdLib.sol";
import "./libs/FarmMechanicsLib.sol";
import "./libs/IRMFLib.sol";
import "../adapters/libs/AmmAdapterIdLib.sol";
import "../integrations/ichi/IICHIVault.sol";

/// @title Earning MERKL rewards by Ichi strategy on Retro
/// @dev 2.0.0: oRETRO transmutation through CASH flash loan
/// @author Alien Deployer (https://github.com/a17)
contract IchiRetroMerklFarmStrategy is LPStrategyBase, MerklStrategyBase, FarmingStrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "2.3.0";

    uint internal constant _PRECISION = 10 ** 18;

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.IchiRetroMerklFarmStrategy")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant ICHIRETROFARMSTRATEGY_STORAGE_LOCATION =
        0x99ebdfe0879c2a352a076e45a49b794cefdc25ad5e938a93a218f6e5a482f300;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error NotFlashPool();
    error PairReentered();

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
                id: StrategyIdLib.ICHI_RETRO_MERKL_FARM,
                platform: addresses[0],
                vault: addresses[1],
                pool: farm.pool,
                underlying: farm.addresses[0]
            })
        );

        __FarmingStrategyBase_init(addresses[0], nums[0]);

        IRMFLib.IchiRetroMerklFarmStrategyStorage storage $ = _getStorage();
        $.paymentToken = farm.addresses[1];
        $.flashPool = farm.addresses[2];
        $.oPool = farm.addresses[3];
        $.uToPaymentTokenPool = farm.addresses[4];
        $.quoter = farm.addresses[5];

        address[] memory _assets = assets();
        address oToken = _getFarmingStrategyBaseStorage()._rewardAssets[0];
        address uToken = IRMFLib.getOtherTokenFromPool(farm.addresses[3], oToken);
        address swapper = IPlatform(addresses[0]).swapper();
        IERC20(_assets[0]).forceApprove(farm.addresses[0], type(uint).max);
        IERC20(_assets[1]).forceApprove(farm.addresses[0], type(uint).max);
        IERC20(farm.addresses[1]).forceApprove(oToken, type(uint).max);
        IERC20(uToken).forceApprove(swapper, type(uint).max);
        IERC20(farm.addresses[1]).forceApprove(swapper, type(uint).max);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CALLBACKS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // Call back function, called by the pair during our flashloan.
    function uniswapV3FlashCallback(uint, uint fee1, bytes calldata) external {
        IRMFLib.IchiRetroMerklFarmStrategyStorage storage $ = _getStorage();
        address flashPool = $.flashPool;
        address paymentToken = $.paymentToken;
        address oToken = _getFarmingStrategyBaseStorage()._rewardAssets[0];
        address uToken = IRMFLib.getOtherTokenFromPool($.oPool, oToken);
        address _platform = platform();

        if (msg.sender != flashPool) {
            revert NotFlashPool();
        }
        if (!$.flashOn) {
            revert PairReentered();
        }

        // Exercise the oToken
        uint paymentTokenAmount = IERC20(paymentToken).balanceOf(address(this));
        uint oTokenAmt = IERC20(oToken).balanceOf(address(this));

        //slither-disable-next-line unused-return
        IOToken(oToken).exercise(oTokenAmt, paymentTokenAmount, address(this));

        // Swap underlying to payment token
        address swapper = IPlatform(_platform).swapper();

        ISwapper.PoolData[] memory route = new ISwapper.PoolData[](1);
        route[0].pool = $.uToPaymentTokenPool;
        route[0].ammAdapter = IPlatform(_platform).ammAdapter(keccak256(bytes(ammAdapterId()))).proxy;
        route[0].tokenIn = uToken;
        route[0].tokenOut = paymentToken;
        ISwapper(swapper).swapWithRoute(
            route, IRMFLib.balance(uToken), LPStrategyLib.SWAP_ASSETS_PRICE_IMPACT_TOLERANCE
        );

        // Pay off our loan
        uint pairDebt = paymentTokenAmount + fee1;
        IERC20(paymentToken).safeTransfer(flashPool, pairDebt);

        $.flashOn = false;
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
    function description() external view returns (string memory) {
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();
        ILPStrategy.LPStrategyBaseStorage storage $lp = _getLPStrategyBaseStorage();
        IFactory.Farm memory farm = IFactory(IPlatform(platform()).factory()).farm($f.farmId);
        return IRMFLib.generateDescription(farm, $lp.ammAdapter);
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x28fffb), bytes3(0x000000)));
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() public view returns (uint[] memory proportions) {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        IICHIVault _underlying = IICHIVault(__$__._underlying);
        proportions = new uint[](2);
        if (_underlying.allowToken0()) {
            proportions[0] = 1e18;
        } else {
            proportions[1] = 1e18;
        }
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
                variants[localTtotal] = IRMFLib.generateDescription(farm, _ammAdapter);
                ++localTtotal;
            }
        }
    }

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.ICHI_RETRO_MERKL_FARM;
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external view override returns (string memory, bool) {
        IFactory.Farm memory farm = _getFarm();
        IICHIVault _ivault = IICHIVault(farm.addresses[0]);
        address allowedToken = _ivault.allowToken0() ? _ivault.token0() : _ivault.token1();
        string memory symbol = IERC20Metadata(allowedToken).symbol();
        return (symbol, false);
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
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        assets_ = __$__._assets;
        uint value = __$__.total;
        IICHIVault _underlying = IICHIVault(__$__._underlying);
        (uint amount0, uint amount1) = _underlying.getTotalAmounts();
        uint totalSupply = _underlying.totalSupply();
        amounts_ = new uint[](2);
        amounts_[0] = amount0 * value / totalSupply;
        amounts_[1] = amount1 * value / totalSupply;
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
        return IRMFLib.claimRevenue(_getStrategyBaseStorage(), _getFarmingStrategyBaseStorage(), _getStorage());
    }

    /// @inheritdoc StrategyBase
    function _depositAssets(uint[] memory amounts, bool) internal override returns (uint value) {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        value = IICHIVault(__$__._underlying).deposit(amounts[0], amounts[1], address(this));
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
        (amountsOut[0], amountsOut[1]) = IICHIVault(__$__._underlying).withdraw(value, receiver);
    }

    /// @inheritdoc StrategyBase
    function _withdrawUnderlying(uint amount, address receiver) internal override {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        IERC20(__$__._underlying).safeTransfer(receiver, amount);
        __$__.total -= amount;
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax)
        internal
        view
        override(StrategyBase, LPStrategyBase)
        returns (uint[] memory amountsConsumed, uint value)
    {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        IICHIVault _underlying = IICHIVault(__$__._underlying);
        amountsConsumed = new uint[](2);
        if (_underlying.allowToken0()) {
            amountsConsumed[0] = amountsMax[0];
        } else {
            amountsConsumed[1] = amountsMax[1];
        }
        uint32 twapPeriod = 600;
        uint price = _fetchSpot(_underlying.token0(), _underlying.token1(), _underlying.currentTick(), _PRECISION);
        uint twap = _fetchTwap(_underlying.pool(), _underlying.token0(), _underlying.token1(), twapPeriod, _PRECISION);
        (uint pool0, uint pool1) = _underlying.getTotalAmounts();
        // aggregated deposit
        uint deposit0PricedInToken1 = (amountsConsumed[0] * ((price < twap) ? price : twap)) / _PRECISION;

        value = amountsConsumed[1] + deposit0PricedInToken1;
        uint totalSupply = _underlying.totalSupply();
        if (totalSupply != 0) {
            uint pool0PricedInToken1 = (pool0 * ((price > twap) ? price : twap)) / _PRECISION;
            value = value * totalSupply / (pool0PricedInToken1 + pool1);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /**
     * @notice returns equivalent _tokenOut for _amountIn, _tokenIn using spot price
     * @param _tokenIn token the input amount is in
     * @param _tokenOut token for the output amount
     * @param _tick tick for the spot price
     * @param _amountIn amount in _tokenIn
     * @return amountOut equivalent anount in _tokenOut
     */
    function _fetchSpot(
        address _tokenIn,
        address _tokenOut,
        int _tick,
        uint _amountIn
    ) internal pure returns (uint amountOut) {
        return IRMFLib.getQuoteAtTick(int24(_tick), SafeCast.toUint128(_amountIn), _tokenIn, _tokenOut);
    }

    /**
     * @notice returns equivalent _tokenOut for _amountIn, _tokenIn using TWAP price
     * @param _pool Pool address to be used for price checking
     * @param _tokenIn token the input amount is in
     * @param _tokenOut token for the output amount
     * @param _twapPeriod the averaging time period
     * @param _amountIn amount in _tokenIn
     * @return amountOut equivalent anount in _tokenOut
     */
    function _fetchTwap(
        address _pool,
        address _tokenIn,
        address _tokenOut,
        uint32 _twapPeriod,
        uint _amountIn
    ) internal view returns (uint amountOut) {
        // Leave twapTick as a int256 to avoid solidity casting
        int twapTick = IRMFLib.consult(_pool, _twapPeriod);
        return IRMFLib.getQuoteAtTick(
            int24(twapTick), // can assume safe being result from consult()
            SafeCast.toUint128(_amountIn),
            _tokenIn,
            _tokenOut
        );
    }

    function _getStorage() private pure returns (IRMFLib.IchiRetroMerklFarmStrategyStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := ICHIRETROFARMSTRATEGY_STORAGE_LOCATION
        }
    }
}
