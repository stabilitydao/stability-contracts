// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LPStrategyBase, StrategyBase, IStrategy, ILPStrategy, IERC165} from "./base/LPStrategyBase.sol";
import {MerklStrategyBase} from "./base/MerklStrategyBase.sol";
import {
    FarmingStrategyBase,
    IFarmingStrategy,
    IControllable,
    IFactory,
    IPlatform,
    StrategyLib
} from "./base/FarmingStrategyBase.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {FarmMechanicsLib} from "./libs/FarmMechanicsLib.sol";
import {QSMFLib} from "./libs/QSMFLib.sol";
import {UniswapV3MathLib} from "./libs/UniswapV3MathLib.sol";
import {INonfungiblePositionManager} from "../integrations/algebra/INonfungiblePositionManager.sol";
import {IAlgebraPool} from "../integrations/algebra/IAlgebraPool.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {AmmAdapterIdLib} from "../adapters/libs/AmmAdapterIdLib.sol";
import {ICAmmAdapter} from "../interfaces/ICAmmAdapter.sol";

/// @title Earning Merkl rewards and swap fees by QuickSwap V3 static liquidity position
/// Changelog
///   1.5.0: decrease code size
/// @author Alien Deployer (https://github.com/a17)
contract QuickSwapStaticMerklFarmStrategy is LPStrategyBase, MerklStrategyBase, FarmingStrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.5.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.QuickSwapV3StaticMerkFarmStrategy")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant QUICKSWAPV3STATICMERKLFARMSTRATEGY_STORAGE_LOCATION =
        0xe97e1b58b908486b9bee3f474a5533db9346238783d026373610f149c8ce1e00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function initialize(address[] memory addresses, uint[] memory nums, int24[] memory ticks) public initializer {
        if (addresses.length != 2 || nums.length != 1 || ticks.length != 0) {
            revert IControllable.IncorrectInitParams();
        }

        IFactory.Farm memory farm = _getFarm(addresses[0], nums[0]);
        if (farm.addresses.length != 1 || farm.nums.length != 0 || farm.ticks.length != 2) {
            revert IFarmingStrategy.BadFarm();
        }
        QSMFLib.QuickswapV3StaticMerklFarmStrategyStorage storage $ = _getQuickStaticFarmStorage();
        $.lowerTick = farm.ticks[0];
        $.upperTick = farm.ticks[1];
        $._nft = INonfungiblePositionManager(farm.addresses[0]);

        __LPStrategyBase_init(
            LPStrategyBaseInitParams({
                id: StrategyIdLib.QUICKSWAP_STATIC_MERKL_FARM,
                platform: addresses[0],
                vault: addresses[1],
                pool: farm.pool,
                underlying: address(0)
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
        override(LPStrategyBase, MerklStrategyBase, FarmingStrategyBase)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IFarmingStrategy
    function canFarm() external pure override returns (bool) {
        return true;
    }

    /// @inheritdoc IStrategy
    function initVariants(address platform_)
        public
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        //slither-disable-next-line unused-return
        return QSMFLib.initVariants(platform_, ammAdapterId(), strategyLogicId());
    }

    /// @inheritdoc IStrategy
    function getRevenue() external view returns (address[] memory __assets, uint[] memory amounts) {
        return QSMFLib.getRevenue(
            pool(), _getQuickStaticFarmStorage(), _getStrategyBaseStorage(), _getFarmingStrategyBaseStorage()
        );
    }

    /// @inheritdoc IStrategy
    function getAssetsProportions() external view returns (uint[] memory proportions) {
        proportions = new uint[](2);
        proportions[0] = _getProportion0(pool());
        proportions[1] = 1e18 - proportions[0];
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0x558ac5), bytes3(0x121319)));
    }

    /// @inheritdoc ILPStrategy
    function ammAdapterId() public pure override returns (string memory) {
        return AmmAdapterIdLib.ALGEBRA;
    }

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.QUICKSWAP_STATIC_MERKL_FARM;
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external view override returns (string memory, bool) {
        IFactory.Farm memory farm = _getFarm();
        return (string.concat(CommonLib.i2s(farm.ticks[0]), " ", CommonLib.i2s(farm.ticks[1])), false);
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();
        ILPStrategy.LPStrategyBaseStorage storage $lp = _getLPStrategyBaseStorage();
        IFactory.Farm memory farm = IFactory(IPlatform(platform()).factory()).farm($f.farmId);
        return QSMFLib.generateDescription(farm, $lp.ammAdapter);
    }

    /// @inheritdoc IStrategy
    function isHardWorkOnDepositAllowed() external pure returns (bool) {}

    /// @inheritdoc IStrategy
    function isReadyForHardWork() external view returns (bool isReady) {
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
    //slither-disable-next-line reentrancy-events
    function _depositAssets(uint[] memory amounts, bool /*claimRevenue*/ ) internal override returns (uint value) {
        QSMFLib.QuickswapV3StaticMerklFarmStrategyStorage storage $ = _getQuickStaticFarmStorage();
        StrategyBaseStorage storage _$ = _getStrategyBaseStorage();
        uint128 liquidity;
        uint tokenId = $._tokenId;
        INonfungiblePositionManager __nft = $._nft;

        // tokenId == 0 mean that there is no NFT managed by the strategy now
        //slither-disable-next-line incorrect-equality
        //slither-disable-next-line timestamp
        if (tokenId == 0) {
            address[] memory _assets = assets();
            //slither-disable-next-line unused-return
            (tokenId, liquidity,,) = __nft.mint(
                INonfungiblePositionManager.MintParams(
                    _assets[0],
                    _assets[1],
                    $.lowerTick,
                    $.upperTick,
                    amounts[0],
                    amounts[1],
                    0,
                    0,
                    address(this),
                    block.timestamp
                )
            );
            $._tokenId = tokenId;
        } else {
            //slither-disable-next-line unused-return
            (liquidity,,) = __nft.increaseLiquidity(
                INonfungiblePositionManager.IncreaseLiquidityParams(
                    tokenId, amounts[0], amounts[1], 0, 0, block.timestamp
                )
            );
        }
        value = uint(liquidity);
        _$.total += value;
    }

    /// @inheritdoc StrategyBase
    //slither-disable-next-line reentrancy-events
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        QSMFLib.QuickswapV3StaticMerklFarmStrategyStorage storage $ = _getQuickStaticFarmStorage();

        amountsOut = new uint[](2);
        uint tokenId = $._tokenId;

        // burn liquidity
        (amountsOut[0], amountsOut[1]) = $._nft.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams(tokenId, uint128(value), 0, 0, block.timestamp)
        );
        {
            // collect tokens and fee
            address[] memory _assets = assets();
            (uint collected0, uint collected1) = $._nft.collect(
                INonfungiblePositionManager.CollectParams(tokenId, address(this), type(uint128).max, type(uint128).max)
            );
            IERC20(_assets[0]).safeTransfer(receiver, amountsOut[0]);
            IERC20(_assets[1]).safeTransfer(receiver, amountsOut[1]);
            uint[] memory fees = new uint[](2);
            fees[0] = collected0 > amountsOut[0] ? (collected0 - amountsOut[0]) : 0;
            fees[1] = collected1 > amountsOut[1] ? (collected1 - amountsOut[1]) : 0;
            emit FeesClaimed(fees);
            //slither-disable-next-line timestamp
            if (fees[0] > 0) {
                _getLPStrategyBaseStorage()._feesOnBalance[0] += fees[0];
            }
            if (fees[1] > 0) {
                _getLPStrategyBaseStorage()._feesOnBalance[1] += fees[1];
            }
        }
        StrategyBaseStorage storage _$_ = _getStrategyBaseStorage();
        uint newTotal = _$_.total - value;
        _$_.total = newTotal;
    }

    /// @inheritdoc StrategyBase
    //slither-disable-next-line reentrancy-events
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
        QSMFLib.QuickswapV3StaticMerklFarmStrategyStorage storage $ = _getQuickStaticFarmStorage();
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        FarmingStrategyBaseStorage storage _$_ = _getFarmingStrategyBaseStorage();
        LPStrategyBaseStorage storage __$ = _getLPStrategyBaseStorage();
        __assets = __$__._assets;
        __rewardAssets = _$_._rewardAssets;
        __amounts = new uint[](2);

        uint tokenId = $._tokenId;
        // nosemgrep
        if (tokenId > 0 && total() > 0) {
            INonfungiblePositionManager __nft = $._nft;
            (__amounts[0], __amounts[1]) = __nft.collect(
                INonfungiblePositionManager.CollectParams({
                    tokenId: tokenId,
                    recipient: address(this),
                    amount0Max: type(uint128).max,
                    amount1Max: type(uint128).max
                })
            );
        }

        __amounts[0] += __$._feesOnBalance[0];
        __$._feesOnBalance[0] = 0;
        __amounts[1] += __$._feesOnBalance[1];
        __$._feesOnBalance[1] = 0;

        uint rwLen = __rewardAssets.length;
        __rewardAmounts = new uint[](rwLen);
        for (uint i; i < rwLen; ++i) {
            __rewardAmounts[i] = StrategyLib.balance(__rewardAssets[i]);
        }
    }

    /// @inheritdoc StrategyBase
    function _compound() internal override {
        (uint[] memory amountsToDeposit) = _swapForDepositProportion(_getProportion0(pool()));
        if (amountsToDeposit[0] > 1 || amountsToDeposit[1] > 1) {
            _depositAssets(amountsToDeposit, false);
        }
    }

    /// @inheritdoc StrategyBase
    function _previewDepositAssets(uint[] memory amountsMax)
        internal
        view
        override(StrategyBase, LPStrategyBase)
        returns (uint[] memory amountsConsumed, uint value)
    {
        QSMFLib.QuickswapV3StaticMerklFarmStrategyStorage storage $ = _getQuickStaticFarmStorage();
        int24[] memory ticks = new int24[](2);
        ticks[0] = $.lowerTick;
        ticks[1] = $.upperTick;
        (value, amountsConsumed) = ICAmmAdapter(address(ammAdapter())).getLiquidityForAmounts(pool(), amountsMax, ticks);
    }

    /// @inheritdoc StrategyBase
    function _assetsAmounts() internal view override returns (address[] memory assets_, uint[] memory amounts_) {
        QSMFLib.QuickswapV3StaticMerklFarmStrategyStorage storage $ = _getQuickStaticFarmStorage();
        int24[] memory ticks = new int24[](2);
        ticks[0] = $.lowerTick;
        ticks[1] = $.upperTick;
        amounts_ = ICAmmAdapter(address(ammAdapter())).getAmountsForLiquidity(
            pool(), ticks, uint128(_getStrategyBaseStorage().total)
        );
        assets_ = assets();
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _getQuickStaticFarmStorage()
        internal
        pure
        returns (QSMFLib.QuickswapV3StaticMerklFarmStrategyStorage storage $)
    {
        //slither-disable-next-line assembly
        assembly {
            $.slot := QUICKSWAPV3STATICMERKLFARMSTRATEGY_STORAGE_LOCATION
        }
    }

    function _getProportion0(address pool_) internal view returns (uint) {
        QSMFLib.QuickswapV3StaticMerklFarmStrategyStorage storage $ = _getQuickStaticFarmStorage();
        int24[] memory ticks = new int24[](2);
        ticks[0] = $.lowerTick;
        ticks[1] = $.upperTick;
        return ICAmmAdapter(address(ammAdapter())).getProportions(pool_, ticks)[0];
    }
}
