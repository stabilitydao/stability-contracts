// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {SiloManagedMerklFarmStrategy} from "../../src/strategies/SiloManagedMerklFarmStrategy.sol";

/// @notice Shared implementation of farms
library SharedFarmMakerLib {
    /// @notice Creates Aave Leverage Merkl Farm configuration
    /// @param aTokenCollateral Address of aToken used as collateral
    /// @param aTokenBorrow Address of aToken used as borrowed asset
    /// @param flashLoanVault Address of the vault used for flash loans
    /// @param rewardAssets Array of reward token addresses
    /// @param minTargetLtv Minimum target loan-to-value ratio (LTV) for leverage management, 85_00 = 0.85
    /// @param maxTargetLtv Maximum target loan-to-value ratio (LTV) for leverage management, 85_00 = 0.85
    /// @param flashLoanKind Type of flash loan to be used (see ILeverageLendingStrategy.FlashLoanKind)
    /// @param eModeCategoryId EMode category ID for the farm (optional, can be 0)
    function _makeAaveLeverageMerklFarm(
        address aTokenCollateral,
        address aTokenBorrow,
        address flashLoanVault,
        address[] memory rewardAssets,
        uint minTargetLtv,
        uint maxTargetLtv,
        uint flashLoanKind,
        uint8 eModeCategoryId
    ) internal pure returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.strategyLogicId = StrategyIdLib.AAVE_LEVERAGE_MERKL_FARM;
        farm.rewardAssets = rewardAssets;

        farm.addresses = new address[](3);
        farm.addresses[0] = aTokenCollateral;
        farm.addresses[1] = aTokenBorrow;
        farm.addresses[2] = flashLoanVault;

        farm.nums = new uint[](4);
        farm.nums[0] = minTargetLtv;
        farm.nums[1] = maxTargetLtv;
        farm.nums[2] = flashLoanKind;
        farm.nums[3] = eModeCategoryId;

        return farm;
    }

}