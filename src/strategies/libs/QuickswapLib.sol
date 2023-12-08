// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/IPlatform.sol";
import "../../interfaces/IFactory.sol";
import "../../interfaces/IAmmAdapter.sol";
import "../../interfaces/IFarmingStrategy.sol";
import "../../core/libs/CommonLib.sol";
import "../../integrations/algebra/IFarmingCenter.sol";

library QuickswapLib {
    using SafeERC20 for IERC20;

    /// @custom:storage-location erc7201:stability.QuickswapV3StaticFarmStrategy
    struct QuickSwapV3StaticFarmStrategyStorage {
        int24 lowerTick;
        int24 upperTick;
        uint _tokenId;
        uint _startTime;
        uint _endTime;
        INonfungiblePositionManager _nft;
        IFarmingCenter _farmingCenter;
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
        for (uint i; i < len; ++i) {
            //nosemgrep
            IFactory.Farm memory farm = farms[i];
            //nosemgrep
            if (farm.status == 0 && CommonLib.eq(farm.strategyLogicId, strategyId)) {
                ++total;
            }
        }

        variants = new string[](total);
        nums = new uint[](total);
        total = 0;
        for (uint i; i < len; ++i) {
            //nosemgrep
            IFactory.Farm memory farm = farms[i];
            //nosemgrep
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

    function getRewards(
        uint __tokenId,
        IFarmingCenter _farmingCenter,
        IncentiveKey memory key
    ) external view returns (uint[] memory amounts) {
        amounts = new uint[](2);
        (amounts[0], amounts[1]) = _farmingCenter.eternalFarming().getRewardInfo(key, __tokenId);
    }

    //slither-disable-next-line reentrancy-events
    function collectRewardsToState(
        QuickSwapV3StaticFarmStrategyStorage storage $,
        IFarmingStrategy.FarmingStrategyBaseStorage storage _$,
        uint tokenId,
        IncentiveKey memory key
    ) external {
        IFarmingCenter farmingCenter = $._farmingCenter;
        (uint reward, uint bonusReward) = farmingCenter.collectRewards(key, tokenId);

        if (reward > 0) {
            address token = _$._rewardAssets[0];
            reward = claimReward(farmingCenter, token, reward);
            _$._rewardsOnBalance[0] += reward;
        }
        if (bonusReward > 0) {
            address token = _$._rewardAssets[1];
            bonusReward = claimReward(farmingCenter, token, bonusReward);
            _$._rewardsOnBalance[1] += bonusReward;
        }

        if (reward > 0 || bonusReward > 0) {
            uint[] memory __rewardAmounts = new uint[](2);
            __rewardAmounts[0] = reward;
            __rewardAmounts[1] = bonusReward;
            emit IFarmingStrategy.RewardsClaimed(__rewardAmounts);
        }
    }

    function claimReward(
        IFarmingCenter farmingCenter,
        address token,
        uint rewardAmount
    ) public returns (uint rewardOut) {
        if (rewardAmount != 0) {
            try farmingCenter.claimReward(token, address(this), 0, rewardAmount) returns (uint /*reward*/ ) {
                rewardOut = rewardAmount;
            } catch {
                // an exception in reward-claiming shouldn't stop hardwork / withdraw
            }
        }
    }
}
