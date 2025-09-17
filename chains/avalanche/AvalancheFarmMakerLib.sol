// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {AvalancheConstantsLib} from "./AvalancheConstantsLib.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {SiloManagedMerklFarmStrategy} from "../../src/strategies/SiloManagedMerklFarmStrategy.sol";

library AvalancheFarmMakerLib {
    function _makeEulerMerklFarm(address vault, address rewardAsset) internal pure returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = address(0);
        farm.strategyLogicId = StrategyIdLib.EULER_MERKL_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = rewardAsset;
        farm.addresses = new address[](3);
        farm.addresses[0] = AvalancheConstantsLib.MERKL_DISTRIBUTOR;
        farm.addresses[1] = vault;
        farm.addresses[2] = AvalancheConstantsLib.TOKEN_REUL;
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeSiloManagedMerklFarm(address managedVault) internal pure returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.strategyLogicId = StrategyIdLib.SILO_MANAGED_MERKL_FARM;

        // we can use getSiloManagedFarmRewards to auto-detect reward assets
        // but some vaults return empty array (probably it's not empty on other blocks)
        farm.rewardAssets = new address[](2);
        farm.rewardAssets[0] = AvalancheConstantsLib.TOKEN_WAVAX;
        farm.rewardAssets[1] = AvalancheConstantsLib.TOKEN_USDC;

        farm.addresses = new address[](2);
        farm.addresses[0] = managedVault;

        // there is xSilo on Avalanche but it's bridged version of the token
        // that doesn't provide i.e. method asset() required by SiloManagedMerklFarmStrategy
        farm.addresses[1] = address(0);

        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    /// @param borrowableCollateral False for non-borrowable ("protected" in ISilo.sol) collateral,
    /// true for borrowable collateral ("collateral" in ISilo.sol)
    function _makeSiloMerklFarm(
        address gauge,
        address siloVault,
        address rewardToken,
        bool borrowableCollateral
    ) internal pure returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.strategyLogicId = StrategyIdLib.SILO_MERKL_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = rewardToken;
        farm.addresses = new address[](3);
        farm.addresses[0] = gauge;
        farm.addresses[1] = siloVault;
        farm.addresses[2] = address(0); // xSilo address, not used on Avalanche (because it's bridged token and doesn't provide interface to swap xSilo to Silo)
        farm.nums = new uint[](1);
        farm.nums[0] = borrowableCollateral ? 1 : 0;
        farm.ticks = new int24[](0);
        return farm;
    }
}