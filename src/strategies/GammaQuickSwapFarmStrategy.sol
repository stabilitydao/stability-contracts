// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./base/LPStrategyBase.sol";
import "./base/FarmingStrategyBase.sol";
import "./libs/StrategyIdLib.sol";
import "./libs/UniswapV3MathLib.sol";
import "./libs/GammaLib.sol";
import "../integrations/gamma/IUniProxy.sol";
import "../integrations/gamma/IHypervisor.sol";
import "../integrations/quickswap/IMasterChef.sol";
import "../integrations/algebra/IAlgebraPool.sol";
import "../integrations/quickswap/IRewarder.sol";
import "../core/libs/CommonLib.sol";
import "../adapters/libs/AmmAdapterIdLib.sol";

/// @title Earning Gamma QuickSwap farm rewards by underlying Gamma Hypervisor
/// @author Alien Deployer (https://github.com/a17)
/// @author JodsMigel (https://github.com/JodsMigel)
contract GammaQuickSwapFarmStrategy is LPStrategyBase, FarmingStrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = '1.0.0';
    
    uint internal constant _PRECISION = 1e36;

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.GammaQuickSwapFarmStrategy")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant GAMMAQUICKSWAPFARMSTRATEGY_STORAGE_LOCATION = 0xe35214fe1ab6125beac0a34cc3d91ce9e661ec11ea224b45538c0becda3e4f00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.GammaQuickSwapFarmStrategy
    struct GammaQuickSwapFarmStrategyStorage {
        IUniProxy uniProxy;
        IMasterChef masterChef;
        uint pid;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function initialize(
        address[] memory addresses,
        uint[] memory nums,
        int24[] memory ticks
    ) public initializer {
        if (addresses.length != 2 || nums.length != 1 || ticks.length != 0) {
            revert IControllable.IncorrectInitParams();
        }

        IFactory.Farm memory farm = _getFarm(addresses[0], nums[0]);
        if (farm.addresses.length != 3 || farm.nums.length != 2 || farm.ticks.length != 0) {
            revert IFarmingStrategy.BadFarm();
        }
        GammaQuickSwapFarmStrategyStorage storage $ = _getGammaQuickStorage();
        $.uniProxy = IUniProxy(farm.addresses[0]);
        $.masterChef = IMasterChef(farm.addresses[1]);
        $.pid = farm.nums[0];

        __LPStrategyBase_init(LPStrategyBaseInitParams({
            id: StrategyIdLib.GAMMA_QUICKSWAP_FARM,
            platform: addresses[0],
            vault: addresses[1],
            pool: farm.pool,
            underlying : farm.addresses[2]
        }));

        __FarmingStrategyBase_init(addresses[0], nums[0]);

        address[] memory _assets = assets(); 
        IERC20(_assets[0]).forceApprove(farm.addresses[2], type(uint).max);
        IERC20(_assets[1]).forceApprove(farm.addresses[2], type(uint).max);
        IERC20(farm.addresses[2]).forceApprove(farm.addresses[1], type(uint).max);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view override (LPStrategyBase, FarmingStrategyBase) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IFarmingStrategy
    function canFarm() external view override returns (bool) {
        GammaQuickSwapFarmStrategyStorage storage $ = _getGammaQuickStorage();
        IMasterChef.PoolInfo memory poolInfo = $.masterChef.poolInfo($.pid);
        return poolInfo.allocPoint > 0;
    }

    /// @inheritdoc ILPStrategy
    function ammAdapterId() public pure override returns(string memory) {
        return AmmAdapterIdLib.ALGEBRA;
    }

    /// @inheritdoc IStrategy
    function getRevenue() external view returns (address[] memory __assets, uint[] memory amounts) {
        __assets = _getFarmingStrategyBaseStorage()._rewardAssets;
        amounts = _getRewards();
    }

    /// @inheritdoc IStrategy
    function initVariants(address platform_) public view returns (
        string[] memory variants,
        address[] memory addresses,
        uint[] memory nums,
        int24[] memory ticks
    ) {
        IAmmAdapter _ammAdapter = IAmmAdapter(IPlatform(platform_).ammAdapter(keccak256(bytes(ammAdapterId()))).proxy);
        addresses = new address[](0);
        ticks = new int24[](0);
    
        IFactory.Farm[] memory farms = IFactory(IPlatform(platform_).factory()).farms();
        uint len = farms.length;
        
        uint total;
        for (uint i; i < len; ++i) {
            IFactory.Farm memory farm = farms[i];
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, STRATEGY_LOGIC_ID())) {
                ++total;
            }
        }

        variants = new string[](total);
        nums = new uint[](total);
        total = 0;
        for (uint i; i < len; ++i) {
            IFactory.Farm memory farm = farms[i];
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, STRATEGY_LOGIC_ID())) {
                nums[total] = i;
                variants[total] = string.concat(
                    "Earn ",
                    CommonLib.implode(CommonLib.getSymbols(farm.rewardAssets), ", "),
                    " on QuickSwap by ",
                    CommonLib.implode(CommonLib.getSymbols(_ammAdapter.poolTokens(farm.pool)), "-"),
                    " Gamma ",
                    GammaLib.getPresetName(farm.nums[1]),
                    " LP"
                );
                ++total;
            }
        }
    }

    /// @inheritdoc IStrategy
    function STRATEGY_LOGIC_ID() public pure override returns(string memory) {
        return StrategyIdLib.GAMMA_QUICKSWAP_FARM;
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() external view returns (uint[] memory proportions) {
        proportions = new uint[](2);
        proportions[0] = _getProportion0(pool());
        proportions[1] = 1e18 - proportions[0];
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0xe9333f), bytes3(0x191b1d)));
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external view override returns (string memory) {
        IFactory.Farm memory farm = _getFarm();
        return GammaLib.getPresetName(farm.nums[1]);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   FARMING STRATEGY BASE                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc FarmingStrategyBase
    function _getRewards() internal view override returns (uint[] memory amounts) {
        uint len = _getFarmingStrategyBaseStorage()._rewardAssets.length;
        GammaQuickSwapFarmStrategyStorage storage $ = _getGammaQuickStorage();
        amounts = new uint[](len);
        for (uint i; i < len; ++i) {
            IRewarder rewarder = IRewarder($.masterChef.getRewarder($.pid, i));
            amounts[i] = rewarder.pendingToken($.pid, address(this));
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _depositAssets(uint[] memory amounts, bool claimRevenue) internal override returns (uint value) {
        GammaQuickSwapFarmStrategyStorage storage $ = _getGammaQuickStorage();
        FarmingStrategyBaseStorage storage _$ = _getFarmingStrategyBaseStorage();
        StrategyBaseStorage storage __$ = _getStrategyBaseStorage();
        if (claimRevenue) {
            (,,,uint[] memory rewardAmounts) = _claimRevenue();
            uint len = rewardAmounts.length;
            for (uint i; i < len; ++i) {
                _$._rewardsOnBalance[i] += rewardAmounts[i];
            }
        }
        uint[4] memory minIn;
        value = $.uniProxy.deposit(amounts[0], amounts[1], address(this), __$._underlying, minIn);
        __$.total += value;
        $.masterChef.deposit($.pid, value, address(this));
    }

    /// @inheritdoc StrategyBase
    function _depositUnderlying(uint amount) internal override returns(uint[] memory amountsConsumed) {
        GammaQuickSwapFarmStrategyStorage storage $ = _getGammaQuickStorage();
        StrategyBaseStorage storage _$ = _getStrategyBaseStorage();
        $.masterChef.deposit($.pid, amount, address(this));
        amountsConsumed = _previewDepositUnderlying(amount);
        _$.total += amount;
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        GammaQuickSwapFarmStrategyStorage storage $ = _getGammaQuickStorage();
        StrategyBaseStorage storage _$ = _getStrategyBaseStorage();
        $.masterChef.withdraw($.pid, value, address(this));
        amountsOut = new uint[](2);
        _$.total -= value;
        uint[4] memory minAmounts;
        (amountsOut[0], amountsOut[1]) = IHypervisor(_$._underlying).withdraw(value, receiver, address(this), minAmounts);
    }

    /// @inheritdoc StrategyBase
    function _withdrawUnderlying(uint amount, address receiver) internal override {
        GammaQuickSwapFarmStrategyStorage storage $ = _getGammaQuickStorage();
        StrategyBaseStorage storage _$ = _getStrategyBaseStorage();
        $.masterChef.withdraw($.pid, amount, address(this));
        IERC20(_$._underlying).safeTransfer(receiver, amount);
        _$.total -= amount;
    }

    /// @inheritdoc StrategyBase
    function _claimRevenue() internal override returns(
        address[] memory __assets,
        uint[] memory __amounts,
        address[] memory __rewardAssets,
        uint[] memory __rewardAmounts
    ) {
        GammaQuickSwapFarmStrategyStorage storage $ = _getGammaQuickStorage();
        StrategyBaseStorage storage _$ = _getStrategyBaseStorage();
        __assets = new address[](2);
        __assets[0] = _$._assets[0];
        __assets[1] = _$._assets[1];
        __amounts = new uint[](2);

        __rewardAssets = _getFarmingStrategyBaseStorage()._rewardAssets;
        uint len = __rewardAssets.length;
        __rewardAmounts = new uint[](len);
        uint[] memory rewardBalanceBefore = new uint[](len);
        for (uint i; i < len; ++i) {
            rewardBalanceBefore[i] = StrategyLib.balance(__rewardAssets[i]);
        }
        $.masterChef.harvest($.pid, address(this));
        for (uint i; i < len; ++i) {
            __rewardAmounts[i] = StrategyLib.balance(__rewardAssets[i]) - rewardBalanceBefore[i];
        }

        // special for farms with first 2 duplicate tokens
        if (len > 1 && __rewardAssets[0] == __rewardAssets[1]) {
            __rewardAmounts[0] = 0;
        }
    }

    /// @inheritdoc StrategyBase
    function _compound() internal override {
        (uint[] memory amountsToDeposit) = _swapForDepositProportion(_getProportion0(pool()));
        if (amountsToDeposit[0] > 1 && amountsToDeposit[1] > 1) {
            uint valueToReceive;
            (amountsToDeposit, valueToReceive) = _previewDepositAssets(amountsToDeposit);
            if (valueToReceive > 10) {
                _depositAssets(amountsToDeposit, false);
            }
        }
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax) internal view override (StrategyBase, LPStrategyBase) returns (uint[] memory amountsConsumed, uint value) {
        // alternative calculation: beefy-contracts/contracts/BIFI/strategies/Gamma/StrategyQuickGamma.sol
        GammaQuickSwapFarmStrategyStorage storage $ = _getGammaQuickStorage();
        StrategyBaseStorage storage _$ = _getStrategyBaseStorage();
        amountsConsumed = new uint[](2);
        address[] memory _assets = assets(); 
        address underlying_ = _$._underlying;
        (uint amount1Start, uint amount1End) = $.uniProxy.getDepositAmount(underlying_, _assets[0], amountsMax[0]);
        if (amountsMax[1] > amount1End) {
            amountsConsumed[0] = amountsMax[0];
            // its possible to be (amount1End + amount1Start) / 2, but current amount1End value pass tests with small amounts
            amountsConsumed[1] = amount1End;
        } else if (amountsMax[1] < amount1Start) {
            //slither-disable-next-line similar-names
            (uint amount0Start, uint amount0End) = $.uniProxy.getDepositAmount(underlying_, _assets[1], amountsMax[1]);
            amountsConsumed[0] = (amount0End + amount0Start) / 2;
            amountsConsumed[1] = amountsMax[1];
        } else {
            amountsConsumed[0] = amountsMax[0];
            amountsConsumed[1] = amountsMax[1];
        }

        // calculate shares
        IHypervisor hypervisor = IHypervisor(underlying_);
        (,int24 tick,,,,,) = IAlgebraPool(pool()).globalState();
        uint160 sqrtPrice = UniswapV3MathLib.getSqrtRatioAtTick(tick);
        uint price = UniswapV3MathLib.mulDiv(uint(sqrtPrice) * uint(sqrtPrice), _PRECISION, 2**(96 * 2));
        (uint pool0, uint pool1) = hypervisor.getTotalAmounts();
        value = amountsConsumed[1] + amountsConsumed[0] * price / _PRECISION;
        uint pool0PricedInToken1 = pool0 * price / _PRECISION;
        value = value * hypervisor.totalSupply() / (pool0PricedInToken1 + pool1);
    }

    /// @inheritdoc StrategyBase
    function _previewDepositUnderlying(uint amount) internal view override returns(uint[] memory amountsConsumed) {
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
            (amounts_[0], amounts_[1]) = (amounts_[0] * _total / totalInHypervisor, amounts_[1] * _total / totalInHypervisor);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev proportion of 1e18
    function _getProportion0(address pool_) internal view returns (uint) {
        IHypervisor hypervisor = IHypervisor(_getStrategyBaseStorage()._underlying);
        //slither-disable-next-line unused-return
        (,int24 tick,,,,,) = IAlgebraPool(pool_).globalState();
        uint160 sqrtPrice = UniswapV3MathLib.getSqrtRatioAtTick(tick);
        uint price = UniswapV3MathLib.mulDiv(uint(sqrtPrice) * uint(sqrtPrice), _PRECISION, 2**(96 * 2));
        (uint pool0, uint pool1) = hypervisor.getTotalAmounts();
        uint pool0PricedInToken1 = pool0 *  price / _PRECISION;
        //slither-disable-next-line divide-before-multiply
        return 1e18 * pool0PricedInToken1 / (pool0PricedInToken1 + pool1);
    }

    function _getGammaQuickStorage() internal pure returns (GammaQuickSwapFarmStrategyStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := GAMMAQUICKSWAPFARMSTRATEGY_STORAGE_LOCATION
        }
    }
}
