// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./base/LPStrategyBase.sol";
import "./base/FarmingStrategyBase.sol";
import "./libs/StrategyIdLib.sol";
import "../adapters/libs/AmmAdapterIdLib.sol";
import {FarmMechanicsLib} from "./libs/FarmMechanicsLib.sol";
import {ILiquidBox} from "../integrations/pearl/ILiquidBox.sol";
import {IUniswapV3Pool} from "../integrations/uniswapv3/IUniswapV3Pool.sol";
import {UniswapV3MathLib} from "./libs/UniswapV3MathLib.sol";
import {ILiquidBoxManager} from "../integrations/pearl/ILiquidBoxManager.sol";
import {IGaugeV2CL} from "../integrations/pearl/IGaugeV2CL.sol";

/// @title Earn Pearl emission by staking Trident ALM tokens to gauge
/// @author Alien Deployer (https://github.com/a17)
contract TridentPearlFarmStrategy is LPStrategyBase, FarmingStrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.2.0";

    uint internal constant _PRECISION = 10 ** 36;

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
                id: StrategyIdLib.TRIDENT_PEARL_FARM,
                platform: addresses[0],
                vault: addresses[1],
                pool: farm.pool,
                underlying: farm.addresses[0]
            })
        );

        __FarmingStrategyBase_init(addresses[0], nums[0]);

        address[] memory _assets = assets();
        IERC20(_assets[0]).forceApprove(farm.addresses[2], type(uint).max);
        IERC20(_assets[1]).forceApprove(farm.addresses[2], type(uint).max);
        IERC20(farm.addresses[0]).forceApprove(farm.addresses[1], type(uint).max);
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
        return AmmAdapterIdLib.UNISWAPV3;
    }

    /// @inheritdoc IStrategy
    function getRevenue() external view returns (address[] memory __assets, uint[] memory amounts) {
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();
        IFactory.Farm memory farm = IFactory(IPlatform(platform()).factory()).farm($f.farmId);
        __assets = $f._rewardAssets;
        amounts = new uint[](1);
        amounts[0] = IGaugeV2CL(farm.addresses[1]).earnedReward(address(this));
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
        return StrategyIdLib.TRIDENT_PEARL_FARM;
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() public view returns (uint[] memory proportions) {
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        LPStrategyBaseStorage storage $lp = _getLPStrategyBaseStorage();
        proportions = new uint[](2);
        (uint total0, uint total1,,,) = ILiquidBox(__$__._underlying).getTotalAmounts();
        uint price = _getPoolPrice($lp.pool);
        uint pool0PricedInToken1 = UniswapV3MathLib.mulDiv(total0, price, _PRECISION);
        if (pool0PricedInToken1 + total1 != 0) {
            proportions[0] = pool0PricedInToken1 * 1e18 / (pool0PricedInToken1 + total1);
        } else {
            proportions[0] = 1e18;
        }
        proportions[1] = 1e18 - proportions[0];
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0xffe300), bytes3(0x004e67)));
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();
        ILPStrategy.LPStrategyBaseStorage storage $lp = _getLPStrategyBaseStorage();
        IFactory.Farm memory farm = IFactory(IPlatform(platform()).factory()).farm($f.farmId);
        return _generateDescription(farm, $lp.ammAdapter);
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external pure override returns (string memory, bool) {
        return ("", false);
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
    function _depositAssets(uint[] memory amounts, bool /*claimRevenue*/ ) internal override returns (uint value) {
        IFactory.Farm memory farm = _getFarm();
        value = ILiquidBoxManager(farm.addresses[2]).deposit(farm.addresses[0], amounts[0], amounts[1], 0, 0);
        if (value != 0) {
            IGaugeV2CL(farm.addresses[1]).deposit(value);
        }
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        __$__.total += value;
    }

    /// @inheritdoc StrategyBase
    function _depositUnderlying(uint amount) internal override returns (uint[] memory amountsConsumed) {
        IFactory.Farm memory farm = _getFarm();
        IGaugeV2CL(farm.addresses[1]).deposit(amount);
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        amountsConsumed = _previewDepositUnderlying(amount);
        __$__.total += amount;
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        amountsOut = new uint[](2);
        IFactory.Farm memory farm = _getFarm();
        IGaugeV2CL(farm.addresses[1]).withdraw(value);
        (amountsOut[0], amountsOut[1]) = ILiquidBoxManager(farm.addresses[2]).withdraw(farm.addresses[0], value, 0, 0);
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        address[] memory _assets = __$__._assets;
        // support of tokens with fee on transfer
        uint bal = StrategyLib.balance(_assets[0]);
        if (bal < amountsOut[0]) {
            amountsOut[0] = bal;
        }
        bal = StrategyLib.balance(_assets[1]);
        if (bal < amountsOut[1]) {
            amountsOut[1] = bal;
        }
        IERC20(_assets[0]).safeTransfer(receiver, amountsOut[0]);
        IERC20(_assets[1]).safeTransfer(receiver, amountsOut[1]);
        __$__.total -= value;
    }

    /// @inheritdoc StrategyBase
    function _withdrawUnderlying(uint amount, address receiver) internal override {
        IFactory.Farm memory farm = _getFarm();
        IGaugeV2CL(farm.addresses[1]).withdraw(amount);
        IERC20(farm.addresses[0]).safeTransfer(receiver, amount);
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        __$__.total -= amount;
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
        IFactory.Farm memory farm = _getFarm();
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        FarmingStrategyBaseStorage storage _$_ = _getFarmingStrategyBaseStorage();
        __assets = __$__._assets;
        __rewardAssets = _$_._rewardAssets;
        __amounts = new uint[](2);
        __rewardAmounts = new uint[](1);
        uint balBefore = IERC20(__rewardAssets[0]).balanceOf(address(this));
        IGaugeV2CL(farm.addresses[1]).collectReward();
        uint balAfter = IERC20(__rewardAssets[0]).balanceOf(address(this));
        __rewardAmounts[0] = balAfter - balBefore;
    }

    /// @inheritdoc StrategyBase
    function _compound() internal override {
        (uint[] memory amountsToDeposit) = _swapForDepositProportion(getAssetsProportions()[0]);
        if (amountsToDeposit[0] != 0 || amountsToDeposit[1] != 0) {
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
        amountsConsumed = new uint[](2);
        IFactory.Farm memory farm = _getFarm();
        address pool = farm.pool;
        address alm = farm.addresses[0];
        (amountsConsumed[0], amountsConsumed[1]) =
            ILiquidBox(alm).getRequiredAmountsForInput(amountsMax[0], amountsMax[1]);
        value = _calcShares(pool, alm, amountsConsumed[0], amountsConsumed[1]);
    }

    /// @inheritdoc StrategyBase
    function _previewDepositUnderlying(uint amount) internal view override returns (uint[] memory amountsConsumed) {
        StrategyBaseStorage storage $ = _getStrategyBaseStorage();
        ILiquidBox alm = ILiquidBox($._underlying);

        (uint total0, uint total1,,,) = alm.getTotalAmounts();
        uint totalInAlm = alm.totalSupply();
        amountsConsumed = new uint[](2);
        amountsConsumed[0] = total0 * amount / totalInAlm;
        amountsConsumed[1] = total1 * amount / totalInAlm;
    }

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        StrategyBaseStorage storage $ = _getStrategyBaseStorage();
        assets_ = $._assets;
        amounts_ = new uint[](2);
        uint _total = $.total;
        if (_total > 0) {
            ILiquidBox alm = ILiquidBox($._underlying);
            (amounts_[0], amounts_[1],,,) = alm.getTotalAmounts();
            uint totalInAlm = alm.totalSupply();
            (amounts_[0], amounts_[1]) = (amounts_[0] * _total / totalInAlm, amounts_[1] * _total / totalInAlm);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _calcShares(address pool, address alm, uint deposit0, uint deposit1) internal view returns (uint shares) {
        uint totalSupply = IERC20(alm).totalSupply();
        (uint total0, uint total1,,,) = ILiquidBox(alm).getTotalAmounts();
        uint price = _getPoolPrice(pool);

        shares = deposit1 + UniswapV3MathLib.mulDiv(deposit0, price, _PRECISION);

        if (totalSupply != 0) {
            uint pool0PricedInToken1 = UniswapV3MathLib.mulDiv(total0, price, _PRECISION);
            shares = UniswapV3MathLib.mulDiv(shares, totalSupply, pool0PricedInToken1 + total1);
        }
    }

    function _getPoolPrice(address pool) internal view returns (uint price) {
        (, int24 tick,,,,,) = IUniswapV3Pool(pool).slot0();
        uint160 sqrtPrice = UniswapV3MathLib.getSqrtRatioAtTick(tick);
        // sqrtPrice < type(uint128).max for maxTick value int24(16777215)
        uint ratioX192 = uint(sqrtPrice) * sqrtPrice;
        price = UniswapV3MathLib.mulDiv(ratioX192, _PRECISION, 1 << 192);
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
            " on Pearl pool ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(_ammAdapter.poolTokens(farm.pool)), "-"),
            " by Trident ALM"
        );
    }
}
