// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStrategy} from "../../interfaces/IStrategy.sol";
import {StrategyLib, IFarmingStrategy} from "../base/FarmingStrategyBase.sol";
import {StrategyIdLib} from "./StrategyIdLib.sol";
import {FarmMechanicsLib} from "./FarmMechanicsLib.sol";
import {IFactory} from "../../interfaces/IFactory.sol";
import {IAmmAdapter} from "../../interfaces/IAmmAdapter.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {CommonLib} from "../../core/libs/CommonLib.sol";
import {AmmAdapterIdLib} from "../../adapters/libs/AmmAdapterIdLib.sol";
import {ISolidlyPool} from "../../integrations/solidly/ISolidlyPool.sol";
import {ISolidlyRouter} from "../../integrations/shadow/ISolidlyRouter.sol";
import {IGauge} from "../../integrations/shadow/IGauge.sol";
import {IXShadow} from "../../integrations/shadow/IXShadow.sol";

/// @title Library for ShF strategy code splitting
library ShFLib {
    using SafeERC20 for IERC20;

    function initVariants(address platform)
        external
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        IAmmAdapter _ammAdapter = IAmmAdapter(IPlatform(platform).ammAdapter(keccak256(bytes(ammAdapterId()))).proxy);
        addresses = new address[](0);
        ticks = new int24[](0);

        IFactory.Farm[] memory farms = IFactory(IPlatform(platform).factory()).farms();
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
                variants[localTtotal] = generateDescription(farm, _ammAdapter);
                ++localTtotal;
            }
        }
    }

    function ammAdapterId() public pure returns (string memory) {
        return AmmAdapterIdLib.SOLIDLY;
    }

    function farmMechanics() external pure returns (string memory) {
        return FarmMechanicsLib.CLASSIC;
    }

    function strategyLogicId() public pure returns (string memory) {
        return StrategyIdLib.SHADOW_FARM;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STRATEGY BASE                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function depositAssets(
        IFactory.Farm memory farm,
        address[] memory assets,
        IStrategy.StrategyBaseStorage storage $base,
        uint[] memory amounts
    ) internal returns (uint value) {
        bool stable = ISolidlyPool(farm.pool).stable();
        (,, value) = ISolidlyRouter(farm.addresses[1]).addLiquidity(
            assets[0], assets[1], stable, amounts[0], amounts[1], 0, 0, address(this), block.timestamp
        );
        IGauge(farm.addresses[0]).deposit(value);
        $base.total += value;
    }

    function depositUnderlying(
        IFactory.Farm memory farm,
        IStrategy.StrategyBaseStorage storage $base,
        uint amount
    ) internal returns (uint[] memory amountsConsumed) {
        IGauge(farm.addresses[0]).deposit(amount);
        $base.total += amount;
        amountsConsumed = ShFLib.calcAssetsAmounts(amount, farm);
    }

    function withdrawAssets(
        IFactory.Farm memory farm,
        address[] memory assets,
        IStrategy.StrategyBaseStorage storage $base,
        uint value,
        address receiver
    ) internal returns (uint[] memory amountsOut) {
        IGauge(farm.addresses[0]).withdraw(value);
        amountsOut = new uint[](2);
        bool stable = ISolidlyPool(farm.pool).stable();
        (amountsOut[0], amountsOut[1]) = ISolidlyRouter(farm.addresses[1]).removeLiquidity(
            assets[0], assets[1], stable, value, 0, 0, receiver, block.timestamp
        );
        $base.total -= value;
    }

    function withdrawUnderlying(
        IFactory.Farm memory farm,
        IStrategy.StrategyBaseStorage storage $base,
        uint amount,
        address receiver
    ) internal {
        IGauge(farm.addresses[0]).withdraw(amount);
        IERC20(farm.pool).safeTransfer(receiver, amount);
        $base.total -= amount;
    }

    function claimRevenue(
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f,
        address[] memory assets,
        IFactory.Farm memory farm
    )
        internal
        returns (
            address[] memory __assets,
            uint[] memory __amounts,
            address[] memory __rewardAssets,
            uint[] memory __rewardAmounts
        )
    {
        __assets = assets;
        __rewardAssets = $f._rewardAssets;
        __amounts = new uint[](__assets.length);
        uint rwLen = __rewardAssets.length;
        uint[] memory balanceBefore = new uint[](rwLen);
        __rewardAmounts = new uint[](rwLen);
        for (uint i; i < rwLen; ++i) {
            balanceBefore[i] = StrategyLib.balance(__rewardAssets[i]);
        }
        IGauge(farm.addresses[0]).getReward(address(this), farm.rewardAssets);
        for (uint i; i < rwLen; ++i) {
            __rewardAmounts[i] = StrategyLib.balance(__rewardAssets[i]) - balanceBefore[i];
        }

        // liquidate xSHADOW to SHADOW
        address xShadow = farm.addresses[2];
        address shadow = IXShadow(xShadow).SHADOW();
        for (uint i; i < rwLen; ++i) {
            if (__rewardAssets[i] == xShadow) {
                if (__rewardAmounts[i] > 0) {
                    __rewardAmounts[i] = IXShadow(xShadow).exit(__rewardAmounts[i]);
                }
                __rewardAssets[i] = shadow;
            }
        }
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function generateDescription(
        IFactory.Farm memory farm,
        IAmmAdapter _ammAdapter
    ) internal view returns (string memory) {
        //slither-disable-next-line calls-loop+
        return string.concat(
            "Earn ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(farm.rewardAssets), ", "),
            " by Shadow classic ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(_ammAdapter.poolTokens(farm.pool)), "-"),
            " ",
            ISolidlyPool(farm.pool).stable() ? "sLP" : "vLP"
        );
    }

    function calcAssetsAmounts(uint shares, IFactory.Farm memory farm) internal view returns (uint[] memory amounts_) {
        address pool = farm.pool;
        (uint reserve0, uint reserve1,) = ISolidlyPool(pool).getReserves();
        uint supply = ISolidlyPool(pool).totalSupply();
        amounts_ = new uint[](2);
        amounts_[0] = reserve0 * shares / supply;
        amounts_[1] = reserve1 * shares / supply;
    }
}
