// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IFactory} from "../../interfaces/IFactory.sol";
import {IAmmAdapter} from "../../interfaces/IAmmAdapter.sol";
import {IFarmingStrategy} from "../../interfaces/IFarmingStrategy.sol";
import {CommonLib} from "../../core/libs/CommonLib.sol";
import {INonfungiblePositionManager} from "../../integrations/algebra/INonfungiblePositionManager.sol";
import {UniswapV3MathLib} from "./UniswapV3MathLib.sol";
import {IAlgebraPool} from "../../integrations/algebra/IAlgebraPool.sol";
import {IStrategy} from "../../interfaces/IStrategy.sol";
import {StrategyLib} from "./StrategyLib.sol";

library QSMFLib {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.QuickSwapV3StaticMerkFarmStrategy
    struct QuickswapV3StaticMerklFarmStrategyStorage {
        int24 lowerTick;
        int24 upperTick;
        uint _tokenId;
        INonfungiblePositionManager _nft;
    }

    function getRevenue(
        address pool,
        QuickswapV3StaticMerklFarmStrategyStorage storage $,
        IStrategy.StrategyBaseStorage storage _$,
        IFarmingStrategy.FarmingStrategyBaseStorage storage __$
    ) external view returns (address[] memory __assets, uint[] memory amounts) {
        {
            uint returnLength = 2 + __$._rewardAssets.length;
            __assets = new address[](returnLength);
            amounts = new uint[](returnLength);
            __assets[0] = _$._assets[0];
            __assets[1] = _$._assets[1];
            for (uint i = 2; i < returnLength; ++i) {
                __assets[i] = __$._rewardAssets[i - 2];
                amounts[i] = StrategyLib.balance(__assets[i]);
            }
        }

        {
            IAlgebraPool _pool = IAlgebraPool(pool);
            uint __tokenId = $._tokenId;
            // get fees
            UniswapV3MathLib.ComputeFeesEarnedCommonParams memory params =
                UniswapV3MathLib.ComputeFeesEarnedCommonParams({tick: 0, lowerTick: 0, upperTick: 0, liquidity: 0});
            (, params.tick,,,,,) = _pool.globalState();
            //slither-disable-next-line similar-names
            uint feeGrowthInside0Last;
            uint feeGrowthInside1Last;
            //slither-disable-next-line similar-names
            uint128 tokensOwed0;
            uint128 tokensOwed1;
            (
                ,,,,
                params.lowerTick,
                params.upperTick,
                params.liquidity,
                feeGrowthInside0Last,
                feeGrowthInside1Last,
                tokensOwed0,
                tokensOwed1
            ) = $._nft.positions(__tokenId);
            //slither-disable-next-line similar-names
            (,, uint feeGrowthOutsideLower0to1, uint feeGrowthOutsideLower1to0,,,,) = _pool.ticks(params.lowerTick);
            //slither-disable-next-line similar-names
            (,, uint feeGrowthOutsideUpper0to1, uint feeGrowthOutsideUpper1to0,,,,) = _pool.ticks(params.upperTick);
            amounts[0] = uint(
                uint128(
                    UniswapV3MathLib.computeFeesEarned(
                        params,
                        _pool.totalFeeGrowth0Token(),
                        feeGrowthOutsideLower0to1,
                        feeGrowthOutsideUpper0to1,
                        feeGrowthInside0Last
                    )
                ) + tokensOwed0
            );
            amounts[1] = uint(
                uint128(
                    UniswapV3MathLib.computeFeesEarned(
                        params,
                        _pool.totalFeeGrowth1Token(),
                        feeGrowthOutsideLower1to0,
                        feeGrowthOutsideUpper1to0,
                        feeGrowthInside1Last
                    )
                ) + tokensOwed1
            );
        }
    }

    function initVariants(
        address platform_,
        string memory ammAdapterId,
        string memory strategyId
    )
        public
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks)
    {
        IAmmAdapter _ammAdapter = IAmmAdapter(IPlatform(platform_).ammAdapter(keccak256(bytes(ammAdapterId))).proxy);
        addresses = new address[](0);
        ticks = new int24[](0);
        IFactory.Farm[] memory farms = IFactory(IPlatform(platform_).factory()).farms();
        uint len = farms.length;
        uint total;
        // nosemgrep
        for (uint i; i < len; ++i) {
            // nosemgrep
            IFactory.Farm memory farm = farms[i];
            // nosemgrep
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, strategyId)) {
                ++total;
            }
        }

        variants = new string[](total);
        nums = new uint[](total);
        total = 0;
        // nosemgrep
        for (uint i; i < len; ++i) {
            // nosemgrep
            IFactory.Farm memory farm = farms[i];
            // nosemgrep
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, strategyId)) {
                nums[total] = i;
                variants[total] = generateDescription(farm, _ammAdapter);
                ++total;
            }
        }
    }

    function generateDescription(
        IFactory.Farm memory farm,
        IAmmAdapter ammAdapter
    ) public view returns (string memory) {
        return string.concat(
            "Earn ",
            CommonLib.implodeSymbols(farm.rewardAssets, ", "),
            " by static position ",
            CommonLib.i2s(farm.ticks[0]),
            "-",
            CommonLib.i2s(farm.ticks[1]),
            " in ",
            CommonLib.implodeSymbols(ammAdapter.poolTokens(farm.pool), "-"),
            " pool on QuickSwapV3"
        );
    }
}
