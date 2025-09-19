// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {IRecoveryContract} from "../../interfaces/IRecoveryContract.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library RevenueRouterLib {
    using SafeERC20 for IERC20;
    /// @notice Send given process of earned tokens to RecoveryContract. Always < DENOMINATOR.
    uint private constant RECOVER_PERCENTAGE = 20_000; // 20%
    uint private constant DENOMINATOR = 100_000; // 100%

    /// @notice Process {assets} and swap them to {stbl} using {swapper} if threshold is met.
    /// Send {RECOVER_PERCENTAGE}% of earned tokens to recovery contract
    /// @param assets List of tokens just withdrawn on balance to process
    /// @param stbl Stbl token
    /// @param swapper Swapper to swap assets to stbl
    /// @param recoveryContract Address of the recovery contract
    function _processAssets(
        address[] memory assets,
        address stbl,
        ISwapper swapper,
        address recoveryContract
    ) internal {
        uint[] memory tempAmounts = new uint[](assets.length);
        uint countNotZeroRecoveryAmounts;
        uint len = assets.length;

        // --------------------- Split earned amounts on parts to swap (80%) and to send to recovery contract (20%)
        for (uint i; i < len; ++i) {
            address asset = assets[i];
            if (asset != stbl) {
                uint threshold = swapper.threshold(asset);
                if (recoveryContract != address(0)) {
                    threshold = threshold * DENOMINATOR / (DENOMINATOR - RECOVER_PERCENTAGE);
                }
                uint amountToSwap = IERC20(asset).balanceOf(address(this));
                if (amountToSwap > threshold) {
                    if (recoveryContract != address(0)) {
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
            (uint[] memory _recoveryAmounts, address[] memory _recoveryAssets) = _removeEmpty(assets, tempAmounts, countNotZeroRecoveryAmounts);

            for (uint i; i < len; ++i) {
                IERC20(_recoveryAssets[i]).safeTransfer(recoveryContract, _recoveryAmounts[i]);
            }
            IRecoveryContract(recoveryContract).registerTransferredAmounts(_recoveryAssets, _recoveryAmounts);
        }
    }

    function _removeEmpty(address[] memory assets, uint[] memory amounts, uint countNotZero)
        private
        pure
        returns (uint[] memory recoveryAmounts, address[] memory recoveryAssets)
    {
        uint len = assets.length;

        recoveryAmounts = new uint[](countNotZero);
        recoveryAssets = new address[](countNotZero);
        countNotZero = 0;
        for (uint i; i < len; ++i) {
            if (amounts[i] != 0) {
                recoveryAmounts[countNotZero] = amounts[i];
                recoveryAssets[countNotZero] = assets[i];
                countNotZero++;
            }
        }
    }
}
