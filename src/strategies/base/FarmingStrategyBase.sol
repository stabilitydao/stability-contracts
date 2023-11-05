// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./StrategyBase.sol";
import "../libs/StrategyLib.sol";
import "../../interfaces/IStrategy.sol";
import "../../interfaces/IFactory.sol";
import "../../interfaces/IFarmingStrategy.sol";
import "../../interfaces/ISwapper.sol";

abstract contract FarmingStrategyBase is StrategyBase, IFarmingStrategy {

    /// @dev Version of FarmingStrategyBase implementation
    string public constant VERSION_FARMING_STRATEGY_BASE = '0.1.0';

    /// @inheritdoc IFarmingStrategy
    uint public farmId;
    
    address[] internal _rewardAssets;
    uint[] internal _rewardsOnBalance;

    /// @dev This empty reserved space is put in place to allow future versions to add new.
    /// variables without shifting down storage in the inheritance chain.
    /// Total gap == 50 - storage slots used.
    uint[50 - 3] private __gap;

    function __FarmingStrategyBase_init(address platform_, uint farmId_) internal onlyInitializing {
        farmId = farmId_;
        _rewardAssets = StrategyLib.FarmingStrategyBase_init(_id, platform_,farmId_);
        _rewardsOnBalance = new uint[](_rewardAssets.length);
    }

    // @dev Calculation of rewards available for claim
    function _getRewards() internal view virtual returns (uint[] memory amounts);

    function _getFarm() internal view returns (IFactory.Farm memory) {
        return _getFarm(platform(), farmId);
    }

    function _getFarm(address platform_, uint farmId_) internal view returns (IFactory.Farm memory) {
        return IFactory(IPlatform(platform_).factory()).farm(farmId_);
    }

    function _liquidateRewards(address exchangeAsset, address[] memory rewardAssets_, uint[] memory rewardAmounts_) internal override returns (uint earnedExchangeAsset) {
        return StrategyLib.liquidateRewards(platform(), exchangeAsset, rewardAssets_, rewardAmounts_);
    }
}
