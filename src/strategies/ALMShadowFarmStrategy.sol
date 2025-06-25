// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ALMStrategyBase} from "./base/ALMStrategyBase.sol";
import {FarmingStrategyBase} from "./base/FarmingStrategyBase.sol";
import {StrategyBase} from "./base/StrategyBase.sol";
import {StrategyIdLib} from "./libs/StrategyIdLib.sol";
import {ALMLib} from "./libs/ALMLib.sol";
import {ALMRamsesV3Lib} from "./libs/ALMRamsesV3Lib.sol";
import {FarmMechanicsLib} from "./libs/FarmMechanicsLib.sol";
import {CommonLib} from "../core/libs/CommonLib.sol";
import {AmmAdapterIdLib} from "../adapters/libs/AmmAdapterIdLib.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IFactory} from "../interfaces/IFactory.sol";
import {IAmmAdapter} from "../interfaces/IAmmAdapter.sol";
import {ILPStrategy} from "../interfaces/ILPStrategy.sol";
import {IFarmingStrategy} from "../interfaces/IFarmingStrategy.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IXShadow} from "../integrations/shadow/IXShadow.sol";

/// @title Earn Shadow gauge rewards by Stability ALM
/// Changelog:
///   1.3.1: Use StrategyBase 2.4.0 - add default poolTvl, maxWithdrawAssets
///   1.3.0: Use StrategyBase 2.3.0 - add fuseMode
///   1.2.0: rebalanceTrigger update
///   1.1.4: FarmingStrategyBase 1.3.3
///   1.1.3: FarmingStrategyBase 1.3.2: refreshFarmingAssets bugfix
///   1.1.2: ALMStrategyBase 1.1.1: Not need re-balance when cant move range
///   1.1.1: LPStrategyBase._swapForDepositProportion use try..catch
///   1.1.0: Fill-Up algo deposits to base range only; improved description
/// @author Alien Deployer (https://github.com/a17)
contract ALMShadowFarmStrategy is ALMStrategyBase, FarmingStrategyBase {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.3.1";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IStrategy
    function initialize(address[] memory addresses, uint[] memory nums, int24[] memory ticks) public initializer {
        if (addresses.length != 2 || nums.length != 1 || ticks.length != 0) {
            revert IControllable.IncorrectInitParams();
        }

        IFactory.Farm memory farm = _getFarm(addresses[0], nums[0]);
        if (farm.addresses.length != 3 || farm.nums.length != 1 || farm.ticks.length != 2) {
            revert IFarmingStrategy.BadFarm();
        }

        __ALMStrategyBase_init(
            LPStrategyBaseInitParams({
                id: StrategyIdLib.ALM_SHADOW_FARM,
                platform: addresses[0],
                vault: addresses[1],
                pool: farm.pool,
                underlying: address(0)
            }),
            ALMStrategyBaseInitParams({algoId: farm.nums[0], params: farm.ticks, nft: farm.addresses[1]})
        );

        __FarmingStrategyBase_init(addresses[0], nums[0]);

        address[] memory _assets = assets();
        IERC20(_assets[0]).forceApprove(farm.addresses[1], type(uint).max);
        IERC20(_assets[1]).forceApprove(farm.addresses[1], type(uint).max);
        address swapper = IPlatform(addresses[0]).swapper();
        IERC20(IXShadow(farm.addresses[2]).SHADOW()).forceApprove(swapper, type(uint).max);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ALMStrategyBase, FarmingStrategyBase)
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
        for (uint i; i < len; ++i) {
            IFactory.Farm memory farm = farms[i];
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, strategyLogicId())) {
                ++localTtotal;
            }
        }

        variants = new string[](localTtotal);
        nums = new uint[](localTtotal);
        localTtotal = 0;
        for (uint i; i < len; ++i) {
            IFactory.Farm memory farm = farms[i];
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
        return total() != 0;
    }

    /// @inheritdoc IFarmingStrategy
    function farmMechanics() external pure returns (string memory) {
        return FarmMechanicsLib.AUTO;
    }

    /// @inheritdoc IStrategy
    function strategyLogicId() public pure override returns (string memory) {
        return StrategyIdLib.ALM_SHADOW_FARM;
    }

    /// @inheritdoc IStrategy
    function extra() external pure returns (bytes32) {
        //slither-disable-next-line too-many-digits
        return CommonLib.bytesToBytes32(abi.encodePacked(bytes3(0xeeeeee), bytes3(0x000000)));
    }

    /// @inheritdoc IStrategy
    function description() external view returns (string memory) {
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f = _getFarmingStrategyBaseStorage();
        IPlatform _platform = IPlatform(platform());
        IFactory.Farm memory farm = IFactory(_platform.factory()).farm($f.farmId);
        IAmmAdapter _ammAdapter = IAmmAdapter(_platform.ammAdapter(keccak256(bytes(ammAdapterId()))).proxy);
        return _generateDescription(farm, _ammAdapter);
    }

    /// @inheritdoc IStrategy
    function getSpecificName() external view override returns (string memory, bool) {
        IFactory.Farm memory farm = _getFarm();
        string memory algo = ALMLib.getAlgoNamyById(farm.nums[0]);
        string memory presetName = ALMLib.getPresetNameByAlgoAndParams(farm.nums[0], farm.ticks);
        return (string.concat(algo, " ", presetName), false);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc StrategyBase
    function _depositAssets(uint[] memory amounts, bool) internal override returns (uint value) {
        return ALMRamsesV3Lib.depositAssets(
            amounts, _getALMStrategyBaseStorage(), _getLPStrategyBaseStorage(), _getStrategyBaseStorage()
        );
    }

    /// @inheritdoc StrategyBase
    function _withdrawAssets(uint value, address receiver) internal override returns (uint[] memory amountsOut) {
        return ALMRamsesV3Lib.withdrawAssets(value, receiver, _getALMStrategyBaseStorage(), _getStrategyBaseStorage());
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
        ALMStrategyBaseStorage storage $ = _getALMStrategyBaseStorage();
        FarmingStrategyBaseStorage storage _$f_ = _getFarmingStrategyBaseStorage();
        StrategyBaseStorage storage __$__ = _getStrategyBaseStorage();
        __assets = __$__._assets;
        __rewardAssets = _$f_._rewardAssets;
        __amounts = new uint[](2);
        ALMRamsesV3Lib.collectFarmRewards($, _$f_);
        __rewardAmounts = _$f_._rewardsOnBalance;
        uint len = __rewardAmounts.length;
        for (uint i; i < len; ++i) {
            _$f_._rewardsOnBalance[i] = 0;
        }

        // liquidate xSHADOW to SHADOW
        IFactory.Farm memory farm = _getFarm();
        address xShadow = farm.addresses[2];
        address shadow = IXShadow(xShadow).SHADOW();
        for (uint i; i < len; ++i) {
            if (__rewardAssets[i] == xShadow) {
                if (__rewardAmounts[i] > 0) {
                    __rewardAmounts[i] = IXShadow(xShadow).exit(__rewardAmounts[i]);
                }
                __rewardAssets[i] = shadow;
            }
        }
    }

    /// @inheritdoc StrategyBase
    function _compound() internal override {
        uint[] memory amountsToDeposit = _swapForDepositProportion(getAssetsProportions()[0]);
        uint valueToReceive;
        (amountsToDeposit, valueToReceive) = _previewDepositAssets(amountsToDeposit);
        if (valueToReceive > 10) {
            _depositAssets(amountsToDeposit, false);
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     ALM STRATEGY BASE                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _rebalance(bool[] memory burnOldPositions, NewPosition[] memory mintNewPositions) internal override {
        ALMRamsesV3Lib.rebalance(
            burnOldPositions,
            mintNewPositions,
            _getALMStrategyBaseStorage(),
            _getLPStrategyBaseStorage(),
            _getFarmingStrategyBaseStorage(),
            _getStrategyBaseStorage()
        );
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _generateDescription(
        IFactory.Farm memory farm,
        IAmmAdapter _ammAdapter
    ) internal view returns (string memory) {
        string memory algo = ALMLib.getAlgoNamyById(farm.nums[0]);
        string memory presetName = ALMLib.getPresetNameByAlgoAndParams(farm.nums[0], farm.ticks);
        //slither-disable-next-line calls-loop
        return string.concat(
            "Earn ",
            CommonLib.implode(CommonLib.getSymbols(farm.rewardAssets), ", "),
            " in Shadow ",
            CommonLib.implode(CommonLib.getSymbols(_ammAdapter.poolTokens(farm.pool)), "-"),
            " pool by Stability ALM with ",
            algo,
            " algo and ",
            presetName,
            " preset (range: ",
            CommonLib.u2s(uint(int(farm.ticks[0]))),
            " ticks, re-balance trigger: ",
            CommonLib.u2s(uint(int(farm.ticks[1]))),
            " ticks)"
        );
    }
}
