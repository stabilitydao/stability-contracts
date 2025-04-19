// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IEVault} from "../../integrations/euler/IEVault.sol";
import {UniswapV3MathLib} from "../libs/UniswapV3MathLib.sol";
import {IUniswapV3Pool} from "../../integrations/uniswapv3/IUniswapV3Pool.sol";
import {IStrategy} from "../../interfaces/IStrategy.sol";
import {IFarmingStrategy} from "../../interfaces/IFarmingStrategy.sol";
import {IFactory} from "../../interfaces/IFactory.sol";
import {StrategyLib} from "./StrategyLib.sol";
import {CommonLib} from "../../core/libs/CommonLib.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IMerklDistributor} from "../../integrations/merkl/IMerklDistributor.sol";

/// @title Library for EMF strategy code splitting
library EMFLib {
    using SafeERC20 for IERC20;

    function initVariants(
        address platform_,
        string memory strategyLogicId
    )
        public
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
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
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, strategyLogicId)) {
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
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, strategyLogicId)) {
                nums[localTtotal] = i;
                //slither-disable-next-line calls-loop
                variants[localTtotal] = generateDescription(farm);
                ++localTtotal;
            }
        }
    }

    function depositAssets(
        uint[] memory amounts,
        bool claimRevenue,
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f,
        IStrategy.StrategyBaseStorage storage $base,
        IFactory.Farm memory farm
    ) external returns (uint value) {
        if (claimRevenue) {
            (,,, uint[] memory rewardAmounts) = _claimRevenue($f, $base, farm);
            uint len = rewardAmounts.length;
            // nosemgrep
            for (uint i; i < len; ++i) {
                // nosemgrep
                $f._rewardsOnBalance[i] += rewardAmounts[i];
            }
        }

        value = IEVault($base._underlying).deposit(amounts[0], address(this));
        $base.total += value;
    }

    function depositUnderlying(
        uint amount,
        IStrategy.StrategyBaseStorage storage $base
    ) external returns (uint[] memory amountsConsumed) {
        amountsConsumed = previewDepositUnderlying(amount, $base);
        $base.total += amount;
    }

    function previewDepositUnderlying(
        uint amount,
        IStrategy.StrategyBaseStorage storage $base
    ) public view returns (uint[] memory amountsConsumed) {
        amountsConsumed = new uint[](1);
        address u = $base._underlying;
        amountsConsumed[0] = IEVault(u).convertToAssets(amount);
    }

    function withdrawAssets(
        uint value,
        address receiver,
        IFactory.Farm memory farm,
        IStrategy.StrategyBaseStorage storage $base
    ) external returns (uint[] memory amountsOut) {
        amountsOut = new uint[](1);
        amountsOut[0] = IEVault(farm.addresses[0]).withdraw(value, receiver, address(this));
        $base.total -= value;
    }

    function withdrawUnderlying(
        uint amount,
        address receiver,
        IFactory.Farm memory farm,
        IStrategy.StrategyBaseStorage storage $base
    ) external {
        IERC20(farm.addresses[0]).safeTransfer(receiver, amount);
        $base.total -= amount;
    }

    function getAssetsProportions() external pure returns (uint[] memory proportions) {
        proportions = new uint[](1);
        proportions[0] = 1e18;
    }

    function _claimRevenue(
        IFarmingStrategy.FarmingStrategyBaseStorage storage $f,
        IStrategy.StrategyBaseStorage storage $base,
        IFactory.Farm memory farm
    )
        public
        returns (
            address[] memory __assets,
            uint[] memory __amounts,
            address[] memory __rewardAssets,
            uint[] memory __rewardAmounts
        )
    {
        __assets = $base._assets;
        __amounts = new uint[](__assets.length);
        __rewardAssets = $f._rewardAssets;
        uint rwLen = __rewardAssets.length;
        uint[] memory balanceBefore = new uint[](rwLen);
        __rewardAmounts = new uint[](rwLen);
        for (uint i; i < rwLen; ++i) {
            balanceBefore[i] = StrategyLib.balance(__rewardAssets[i]);
        }
        // call claim() here
        // IMerklDistributor(farm.addresses[1]).claim(users, tokens, amounts, proofs);
        for (uint i; i < rwLen; ++i) {
            __rewardAmounts[i] = StrategyLib.balance(__rewardAssets[i]) - balanceBefore[i];
        }
    }

    function previewDepositAssets(
        uint[] memory amountsMax,
        IStrategy.StrategyBaseStorage storage $base
    ) external view returns (uint[] memory amountsConsumed, uint value) {
        amountsConsumed = new uint[](1);
        amountsConsumed[0] = amountsMax[0];
        value = IEVault($base._underlying).convertToShares(amountsMax[0]);
    }

    function generateDescription(IFactory.Farm memory farm) public view returns (string memory) {
        //slither-disable-next-line calls-loop
        return string.concat(
            "Lend ",
            //slither-disable-next-line calls-loop
            IERC20Metadata(IEVault(farm.addresses[1]).asset()).symbol(),
            " on Euler and earn ",
            //slither-disable-next-line calls-loop
            CommonLib.implode(CommonLib.getSymbols(farm.rewardAssets), ", "),
            " Merkl rewards"
        );
    }
}
