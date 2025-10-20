// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {IRecovery} from "../../interfaces/IRecovery.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library RevenueRouterLib {
    using SafeERC20 for IERC20;
    /// @notice Send given process of earned tokens to Recovery.sol. Always < DENOMINATOR.

    uint internal constant RECOVER_PERCENTAGE = 20_000; // 20%
    uint internal constant DENOMINATOR = 100_000; // 100%

    /// @notice Process {assets} and swap them to {stbl} using {swapper} if threshold is met.
    /// Send {RECOVER_PERCENTAGE}% of earned tokens to recovery contract
    /// @param assets List of tokens just withdrawn on balance to process
    /// @param stbl Stbl token
    /// @param swapper Swapper to swap assets to stbl
    /// @param recovery_ Address of the recovery contract
    function processAssets(address[] memory assets, address stbl, ISwapper swapper, address recovery_) internal {
        uint[] memory tempAmounts = new uint[](assets.length);
        uint countNotZeroRecoveryAmounts;
        uint len = assets.length;

        // --------------------- Split earned amounts on parts to swap (80%) to STBL and to send to recovery contract (20%)
        for (uint i; i < len; ++i) {
            address asset = assets[i];

            // we assume that amounts cannot be earned in STBL, so we don't need to pay 20% of STBL to recovery contract
            if (asset != stbl) {
                uint threshold = swapper.threshold(asset);
                if (recovery_ != address(0)) {
                    threshold = threshold * DENOMINATOR / (DENOMINATOR - RECOVER_PERCENTAGE);
                }
                uint amountToSwap = IERC20(asset).balanceOf(address(this));
                if (amountToSwap > threshold) {
                    if (recovery_ != address(0)) {
                        tempAmounts[i] = amountToSwap * RECOVER_PERCENTAGE / DENOMINATOR;
                        amountToSwap -= tempAmounts[i];
                        countNotZeroRecoveryAmounts++;
                    }

                    IERC20(asset).forceApprove(address(swapper), amountToSwap);
                    try swapper.swap(asset, stbl, amountToSwap, 20_000) {} catch {}
                }
            }
        }

        // --------------------- Process not-zero recovery amounts
        if (countNotZeroRecoveryAmounts != 0) {
            (address[] memory _recoveryAssets, uint[] memory _recoveryAmounts) =
                removeEmpty(assets, tempAmounts, countNotZeroRecoveryAmounts);

            for (uint i; i < _recoveryAssets.length; ++i) {
                IERC20(_recoveryAssets[i]).safeTransfer(recovery_, _recoveryAmounts[i]);
            }
            IRecovery(recovery_).registerAssets(_recoveryAssets);
        }
    }

    /// @notice Get first {countNotZero} non-zero amounts from {amounts} and corresponding assets from {assets}
    /// and save only items with non-zero amounts in the result arrays
    function removeEmpty(
        address[] memory assets,
        uint[] memory amounts,
        uint countNotZero
    ) internal pure returns (address[] memory recoveryAssets, uint[] memory recoveryAmounts) {
        // assume here that lengths of both arrays are equal

        uint len = assets.length;

        recoveryAmounts = new uint[](countNotZero);
        recoveryAssets = new address[](countNotZero);

        uint index = 0;
        for (uint i; i < len; ++i) {
            if (amounts[i] != 0) {
                recoveryAmounts[index] = amounts[i];
                recoveryAssets[index] = assets[i];
                index++;
            }
        }
    }
}
