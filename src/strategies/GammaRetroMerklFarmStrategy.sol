// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LPStrategyBase, ILPStrategy, StrategyBase, IStrategy, IERC165} from "./base/LPStrategyBase.sol";
import {MerklStrategyBase} from "./base/MerklStrategyBase.sol";
import {FarmingStrategyBase, IFarmingStrategy, IControllable} from "./base/FarmingStrategyBase.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {FarmMechanicsLib} from "./libs/FarmMechanicsLib.sol";
import {UniswapV3MathLib} from "./libs/UniswapV3MathLib.sol";
import {ALMPositionNameLib} from "./libs/ALMPositionNameLib.sol";
import {GRMFLib} from "./libs/GRMFLib.sol";
import {StrategyLib} from "./libs/StrategyLib.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IUniProxy} from "../integrations/gamma/IUniProxy.sol";
import {IHypervisor} from "../integrations/gamma/IHypervisor.sol";
import {IUniswapV3Pool} from "../integrations/uniswapv3/IUniswapV3Pool.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {AmmAdapterIdLib} from "../adapters/libs/AmmAdapterIdLib.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";

/// @title Earning Merkl rewards on Retro by underlying Gamma Hypervisor
/// Changelog
///   2.5.0: decrease code size
///   2.4.0: decrease code size
///   2.3.0: getCustomVaultFee support
///   2.2.1: LPStrategyBase 1.0.3
///   2.2.0: FarmingStrategyBase 1.1.2
///   2.1.0: add MerklStrategyBase
///   2.0.0: oRETRO transmutation through CASH flash loan
/// @author Alien Deployer (https://github.com/a17)
contract GammaRetroMerklFarmStrategy is LPStrategyBase, MerklStrategyBase, FarmingStrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "2.5.0";

    uint internal constant _PRECISION = 1e36;

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.GammaRetroFarmStrategy")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant GAMMARETROFARMSTRATEGY_STORAGE_LOCATION =
        0x46595ab865e543d547ad8669c6b3d688cf90b51012c63b16ac16869cad017f00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function initialize(address[] memory addresses, uint[] memory nums, int24[] memory ticks) public initializer {
        if (addresses.length != 2 || nums.length != 1 || ticks.length != 0) {
            revert IControllable.IncorrectInitParams();
        }

        IFactory.Farm memory farm = _getFarm(addresses[0], nums[0]);
        if (farm.addresses.length != 7 || farm.nums.length != 1 || farm.ticks.length != 0) {
            revert IFarmingStrategy.BadFarm();
        }
        GRMFLib.GammaRetroFarmStrategyStorage storage $ = _getGammaRetroStorage();
        $.uniProxy = IUniProxy(farm.addresses[0]);

        __LPStrategyBase_init(
            LPStrategyBaseInitParams({
                id: strategyLogicId(),
                platform: addresses[0],
                vault: addresses[1],
                pool: farm.pool,
                underlying: farm.addresses[1]
            })
        );

        __FarmingStrategyBase_init(addresses[0], nums[0]);

        $.paymentToken = farm.addresses[2];
        $.flashPool = farm.addresses[3];
        $.oPool = farm.addresses[4];
        $.uToPaymentTokenPool = farm.addresses[5];
        $.quoter = farm.addresses[6];

        address[] memory _assets = assets();
        address oToken = _getFarmingStrategyBaseStorage()._rewardAssets[0];
        address uToken = GRMFLib.getOtherTokenFromPool(farm.addresses[4], oToken);
        address swapper = IPlatform(addresses[0]).swapper();
        IERC20(_assets[0]).forceApprove(farm.addresses[1], type(uint).max);
        IERC20(_assets[1]).forceApprove(farm.addresses[1], type(uint).max);
        IERC20(farm.addresses[2]).forceApprove(oToken, type(uint).max);
        IERC20(uToken).forceApprove(swapper, type(uint).max);
        IERC20(farm.addresses[2]).forceApprove(swapper, type(uint).max);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CALLBACKS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    // Call back function, called by the pair during our flashloan.
    function uniswapV3FlashCallback(uint, uint fee1, bytes calldata) external {
        GRMFLib.uniswapV3FlashCallback(
            platform(), ammAdapterId(), _getGammaRetroStorage(), _getFarmingStrategyBaseStorage(), fee1
        );
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
        return GRMFLib.initVariants(platform_, strategyLogicId(), ammAdapterId());
    }

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.GAMMA_RETRO_MERKL_FARM;
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() external view returns (uint[] memory proportions) {
        proportions = new uint[](2);
        proportions[0] = _getProportion0(pool());
        proportions[1] = 1e18 - proportions[0];
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0xff0000), bytes3(0x000000)));
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external view override returns (string memory, bool) {
        IFactory.Farm memory farm = _getFarm();
        return (ALMPositionNameLib.getName(farm.nums[0]), true);
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();
        ILPStrategy.LPStrategyBaseStorage storage $lp = _getLPStrategyBaseStorage();
        IFactory.Farm memory farm = IFactory(IPlatform(platform()).factory()).farm($f.farmId);
        return GRMFLib.generateDescription(farm, $lp.ammAdapter);
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
    function _depositAssets(uint[] memory amounts, bool) internal override returns (uint value) {
        GRMFLib.GammaRetroFarmStrategyStorage storage $ = _getGammaRetroStorage();
        StrategyBaseStorage storage __$ = _getStrategyBaseStorage();
        //slither-disable-next-line uninitialized-local
        uint[4] memory minIn;
        value = $.uniProxy.deposit(amounts[0], amounts[1], address(this), __$._underlying, minIn);
        __$.total += value;
    }

    /// @inheritdoc StrategyBase
    function _depositUnderlying(uint amount) internal override returns (uint[] memory amountsConsumed) {
        StrategyBaseStorage storage _$ = _getStrategyBaseStorage();
        amountsConsumed = _previewDepositUnderlying(amount);
        _$.total += amount;
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        StrategyBaseStorage storage _$ = _getStrategyBaseStorage();
        amountsOut = new uint[](2);
        _$.total -= value;
        //slither-disable-next-line uninitialized-local
        uint[4] memory minAmounts;
        (amountsOut[0], amountsOut[1]) =
            IHypervisor(_$._underlying).withdraw(value, receiver, address(this), minAmounts);
    }

    /// @inheritdoc StrategyBase
    function _withdrawUnderlying(uint amount, address receiver) internal override {
        StrategyBaseStorage storage _$ = _getStrategyBaseStorage();
        IERC20(_$._underlying).safeTransfer(receiver, amount);
        _$.total -= amount;
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
        return
            GRMFLib.claimRevenue(_getStrategyBaseStorage(), _getFarmingStrategyBaseStorage(), _getGammaRetroStorage());
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
        // alternative calculation: beefy-contracts/contracts/BIFI/strategies/Gamma/StrategyQuickGamma.sol
        GRMFLib.GammaRetroFarmStrategyStorage storage $ = _getGammaRetroStorage();
        StrategyBaseStorage storage _$ = _getStrategyBaseStorage();
        amountsConsumed = new uint[](2);
        address[] memory _assets = assets();
        address underlying_ = _$._underlying;
        (uint amount1Start, uint amount1End) = $.uniProxy.getDepositAmount(underlying_, _assets[0], amountsMax[0]);
        if (amountsMax[1] > amount1End) {
            amountsConsumed[0] = amountsMax[0];
            // its possible to be (amount1End + amount1Start) / 2, but current amount1End value pass tests with small amounts
            amountsConsumed[1] = amount1End;
        } else if (amountsMax[1] <= amount1Start) {
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
        //slither-disable-next-line unused-return
        (, int24 tick,,,,,) = IUniswapV3Pool(pool()).slot0();
        uint160 sqrtPrice = UniswapV3MathLib.getSqrtRatioAtTick(tick);
        uint price = UniswapV3MathLib.mulDiv(uint(sqrtPrice) * uint(sqrtPrice), _PRECISION, 2 ** (96 * 2));
        (uint pool0, uint pool1) = hypervisor.getTotalAmounts();
        value = amountsConsumed[1] + amountsConsumed[0] * price / _PRECISION;
        uint pool0PricedInToken1 = pool0 * price / _PRECISION;
        value = value * hypervisor.totalSupply() / (pool0PricedInToken1 + pool1);
    }

    /// @inheritdoc StrategyBase
    function _previewDepositUnderlying(uint amount) internal view override returns (uint[] memory amountsConsumed) {
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
            (amounts_[0], amounts_[1]) =
                (amounts_[0] * _total / totalInHypervisor, amounts_[1] * _total / totalInHypervisor);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev proportion of 1e18
    function _getProportion0(address pool_) internal view returns (uint) {
        return GRMFLib.getProportion0(pool_, _getStrategyBaseStorage()._underlying);
    }

    function _getGammaRetroStorage() private pure returns (GRMFLib.GammaRetroFarmStrategyStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := GAMMARETROFARMSTRATEGY_STORAGE_LOCATION
        }
    }
}
