// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "../../interfaces/IPlatform.sol";
import "../../interfaces/IFactory.sol";
import "../../interfaces/IDexAdapter.sol";
import "../../core/libs/CommonLib.sol";

library QuickswapLib {
    function initVariants(address platform_, string memory dexAdapterId, string memory strategyId) public view returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks) {
        IDexAdapter _dexAdapter = IDexAdapter(IPlatform(platform_).dexAdapter(keccak256(bytes(dexAdapterId))).proxy);
        addresses = new address[](0);
        ticks = new int24[](0);
        IFactory.Farm[] memory farms = IFactory(IPlatform(platform_).factory()).farms();
        uint len = farms.length;
        uint total;
        for (uint i; i < len; ++i) {
            IFactory.Farm memory farm = farms[i];
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, strategyId)) {
                ++total;
            }
        }

        variants = new string[](total);
        nums = new uint[](total);
        total = 0;
        for (uint i; i < len; ++i) {
            IFactory.Farm memory farm = farms[i];
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
                    CommonLib.implodeSymbols(_dexAdapter.poolTokens(farm.pool), "-"),
                    " pool on QuickSwapV3"
                );
                ++total;
            }
        }
    }
}