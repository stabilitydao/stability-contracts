// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../../interfaces/IPlatform.sol";
import "../../interfaces/IFactory.sol";
import "../../interfaces/IAmmAdapter.sol";
import "../../core/libs/CommonLib.sol";

library QuickswapLib {
    function initVariants(address platform_, string memory ammAdapterId, string memory strategyId) public view returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks) {
        IAmmAdapter _ammAdapter = IAmmAdapter(IPlatform(platform_).ammAdapter(keccak256(bytes(ammAdapterId))).proxy);
        addresses = new address[](0);
        ticks = new int24[](0);
        IFactory.Farm[] memory farms = IFactory(IPlatform(platform_).factory()).farms();
        uint len = farms.length;
        uint total;
        for (uint i; i < len; ++i) { // nosemgrep
            IFactory.Farm memory farm = farms[i];
            // nosemgrep
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, strategyId)) {
                ++total;
            }
        }

        variants = new string[](total);
        nums = new uint[](total);
        total = 0;
        for (uint i; i < len; ++i) { // nosemgrep
            IFactory.Farm memory farm = farms[i];
            // nosemgrep
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, strategyId)) {
                nums[total] = i;
                variants[total] = string.concat(
                    "Earn ",
                    CommonLib.implodeSymbols(farm.rewardAssets, ", "),
                    " by static position ",
                    CommonLib.i2s(farm.ticks[0]),
                    "-",
                    CommonLib.i2s(farm.ticks[1]),
                    " in ",
                    CommonLib.implodeSymbols(_ammAdapter.poolTokens(farm.pool), "-"),
                    " pool on QuickSwapV3"
                );
                ++total;
            }
        }
    }
}