// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./base/PairStrategyBase.sol";
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
import "../adapters/libs/DexAdapterIdLib.sol";

/// @title Earning Gamma QuickSwap farm rewards by underlying Gamma Hypervisor
/// @author Alien Deployer (https://github.com/a17)
contract GammaQuickSwapFarmStrategy is PairStrategyBase, FarmingStrategyBase {
    using SafeERC20 for IERC20;

    /// @dev Version of GammaQuickSwapFarmStrategy implementation
    string public constant VERSION = '1.0.0';
    
    uint internal constant _PRECISION = 1e36;

    IUniProxy public uniProxy;
    IMasterChef public masterChef;
    uint public pid;

    /// @dev This empty reserved space is put in place to allow future versions to add new.
    /// variables without shifting down storage in the inheritance chain.
    /// Total gap == 50 - storage slots used.
    uint[50 - 3] private __gap;

    /// @inheritdoc IStrategy
    function initialize(
        address[] memory addresses,
        uint[] memory nums,
        int24[] memory ticks
    ) public initializer {
        require(addresses.length == 2 && nums.length == 1 && ticks.length == 0, "GQF: bad params");

        IFactory.Farm memory farm = _getFarm(addresses[0], nums[0]);
        require(farm.addresses.length == 3 && farm.nums.length == 2 && farm.ticks.length == 0, "GQF: bad farm");
        uniProxy = IUniProxy(farm.addresses[0]);
        masterChef = IMasterChef(farm.addresses[1]);
        pid = farm.nums[0];

        __PairStrategyBase_init(PairStrategyBaseInitParams({
            id: StrategyIdLib.GAMMA_QUICKSWAP_FARM,
            platform: addresses[0],
            vault: addresses[1],
            pool: farm.pool,
            underlying : farm.addresses[2]
        }));

        __FarmingStrategyBase_init(addresses[0], nums[0]);

        IERC20(_assets[0]).approve(farm.addresses[2], type(uint).max);
        IERC20(_assets[1]).approve(farm.addresses[2], type(uint).max);
        IERC20(farm.addresses[2]).approve(farm.addresses[1], type(uint).max);
    }

    function initVariants(address platform_) public view returns (
        string[] memory variants,
        address[] memory addresses,
        uint[] memory nums,
        int24[] memory ticks
    ) {
        IDexAdapter _dexAdapter = IDexAdapter(IPlatform(platform_).dexAdapter(keccak256(bytes(DEX_ADAPTER_ID()))).proxy);
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
                    CommonLib.implode(CommonLib.getSymbols(_dexAdapter.poolTokens(farm.pool)), "-"),
                    " Gamma ",
                    GammaLib.getPresetName(farm.nums[1]),
                    " LP"
                );
                ++total;
            }
        }
    }

    function canFarm() external view override returns (bool) {
        IMasterChef.PoolInfo memory poolInfo = masterChef.poolInfo(pid);
        return poolInfo.allocPoint > 0;
    }

    function getRevenue() external view returns (address[] memory __assets, uint[] memory amounts) {
        __assets = _rewardAssets;
        amounts = _getRewards();
    }

    /// @inheritdoc IPairStrategyBase
    function DEX_ADAPTER_ID() public pure override returns(string memory) {
        return DexAdapterIdLib.ALGEBRA;
    }

    function STRATEGY_LOGIC_ID() public pure override returns(string memory) {
        return StrategyIdLib.GAMMA_QUICKSWAP_FARM;
    }

    function _previewDepositAssets(uint[] memory amountsMax) internal view override (StrategyBase, PairStrategyBase) returns (uint[] memory amountsConsumed, uint value) {
        // alternative calculation: beefy-contracts/contracts/BIFI/strategies/Gamma/StrategyQuickGamma.sol
        amountsConsumed = new uint[](2);
        (uint amount1Start, uint amount1End) = uniProxy.getDepositAmount(_underlying, _assets[0], amountsMax[0]);
        if (amountsMax[1] > amount1End) {
            amountsConsumed[0] = amountsMax[0];
            // its possible to be (amount1End + amount1Start) / 2, but current amount1End value pass tests with small amounts
            amountsConsumed[1] = amount1End;
        } else if (amountsMax[1] < amount1Start) {
            (uint amount0Start, uint amount0End) = uniProxy.getDepositAmount(_underlying, _assets[1], amountsMax[1]);
            amountsConsumed[0] = (amount0End + amount0Start) / 2;
            amountsConsumed[1] = amountsMax[1];
        } else {
            amountsConsumed[0] = amountsMax[0];
            amountsConsumed[1] = amountsMax[1];
        }

        // calculate shares
        IHypervisor hypervisor = IHypervisor(_underlying);
        IAlgebraPool _pool = IAlgebraPool(pool);
        (,int24 tick,,,,,) = _pool.globalState();
        uint160 sqrtPrice = UniswapV3MathLib.getSqrtRatioAtTick(tick);
        uint price = UniswapV3MathLib.mulDiv(uint(sqrtPrice) * uint(sqrtPrice), _PRECISION, 2**(96 * 2));
        (uint pool0, uint pool1) = hypervisor.getTotalAmounts();
        value = amountsConsumed[1] + amountsConsumed[0] * price / _PRECISION;
        uint pool0PricedInToken1 = pool0 * price / _PRECISION;
        value = value * hypervisor.totalSupply() / (pool0PricedInToken1 + pool1);
    }

    function _previewDepositUnderlying(uint amount) internal view override returns(uint[] memory amountsConsumed) {
        IHypervisor hypervisor = IHypervisor(_underlying);
        (uint pool0, uint pool1) = hypervisor.getTotalAmounts();
        uint _total = hypervisor.totalSupply();
        amountsConsumed = new uint[](2);
        amountsConsumed[0] = amount * pool0 / _total;
        amountsConsumed[1] = amount * pool1 / _total;
    }

    function getAssetsProportions() external view returns (uint[] memory proportions) {
        proportions = new uint[](2);
        proportions[0] = _getProportion0(pool);
        proportions[1] = 1e18 - proportions[0];
    }

    /// @dev proportion of 1e18
    function _getProportion0(address pool_) internal view returns (uint) {
        IHypervisor hypervisor = IHypervisor(_underlying);
        (,int24 tick,,,,,) = IAlgebraPool(pool_).globalState();
        uint160 sqrtPrice = UniswapV3MathLib.getSqrtRatioAtTick(tick);
        uint price = UniswapV3MathLib.mulDiv(uint(sqrtPrice) * uint(sqrtPrice), _PRECISION, 2**(96 * 2));
        (uint pool0, uint pool1) = hypervisor.getTotalAmounts();
        uint pool0PricedInToken1 = pool0 *  price / _PRECISION;
        return pool0PricedInToken1 * 1e18 / (pool0PricedInToken1 + pool1);
    }

    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        assets_ = _assets;
        amounts_ = new uint[](2);
        uint _total = total;
        if (_total > 0) {
            IHypervisor hypervisor = IHypervisor(_underlying);
            (amounts_[0], amounts_[1]) = hypervisor.getTotalAmounts();
            uint totalInHypervisor = hypervisor.totalSupply();
            (amounts_[0], amounts_[1]) = (amounts_[0] * _total / totalInHypervisor, amounts_[1] * _total / totalInHypervisor);
        }
    }

    function _depositAssets(uint[] memory amounts, bool claimRevenue) internal override returns (uint value) {
        if (claimRevenue) {
            (,,,uint[] memory rewardAmounts) = _claimRevenue();
            uint len = rewardAmounts.length;
            for (uint i; i < len; ++i) {
                _rewardsOnBalance[i] += rewardAmounts[i];
            }
        }
        uint[4] memory minIn;
        value = uniProxy.deposit(amounts[0], amounts[1], address(this), _underlying, minIn);
        total += value;
        masterChef.deposit(pid, value, address(this));
    }

    function _depositUnderlying(uint amount) internal override returns(uint[] memory amountsConsumed) {
        masterChef.deposit(pid, amount, address(this));
        amountsConsumed = _previewDepositUnderlying(amount);
        total += amount;
    }

    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        masterChef.withdraw(pid, value, address(this));
        amountsOut = new uint[](2);
        total -= value;
        uint[4] memory minAmounts;
        (amountsOut[0], amountsOut[1]) = IHypervisor(_underlying).withdraw(value, receiver, address(this), minAmounts);
    }

    function _withdrawUnderlying(uint amount, address receiver) internal override {
        masterChef.withdraw(pid, amount, address(this));
        IERC20(_underlying).safeTransfer(receiver, amount);
        total -= amount;
    }

    function _claimRevenue() internal override returns(
        address[] memory __assets,
        uint[] memory __amounts,
        address[] memory __rewardAssets,
        uint[] memory __rewardAmounts
    ) {
        __assets = new address[](2);
        __assets[0] = _assets[0];
        __assets[1] = _assets[1];
        __amounts = new uint[](2);

        __rewardAssets = _rewardAssets;
        uint len = __rewardAssets.length;
        __rewardAmounts = new uint[](len);
        uint[] memory rewardBalanceBefore = new uint[](len);
        for (uint i; i < len; ++i) {
            rewardBalanceBefore[i] = StrategyLib.balance(__rewardAssets[i]);
        }
        masterChef.harvest(pid, address(this));
        for (uint i; i < len; ++i) {
            __rewardAmounts[i] = StrategyLib.balance(__rewardAssets[i]) - rewardBalanceBefore[i];
        }

        // special for farms with first 2 duplicate tokens
        if (len > 1 && __rewardAssets[0] == __rewardAssets[1]) {
            __rewardAmounts[0] = 0;
        }
    }

    function _compound() internal override {
        (uint[] memory amountsToDeposit) = _swapForDepositProportion(_getProportion0(pool));
        if (amountsToDeposit[0] > 1 && amountsToDeposit[1] > 1) {
            uint valueToReceive;
            (amountsToDeposit, valueToReceive) = _previewDepositAssets(amountsToDeposit);
            if (valueToReceive > 10) {
                _depositAssets(amountsToDeposit, false);
            }
        }
    }

    function getSpecificName() external view override returns (string memory) {
        IFactory.Farm memory farm = _getFarm();
        return GammaLib.getPresetName(farm.nums[1]);
    }

    function extra() external pure returns (bytes32) {
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0xe9333f), bytes3(0x191b1d)));
    }

    // @dev See {FarmingStrategyBase-_getRewards}
    function _getRewards() internal view override returns (uint[] memory amounts) {
        uint len = _rewardAssets.length;
        amounts = new uint[](len);
        for (uint i; i < len; ++i) {
            IRewarder rewarder = IRewarder(masterChef.getRewarder(pid, i));
            amounts[i] = rewarder.pendingToken(pid, address(this));
        }
    }
}
