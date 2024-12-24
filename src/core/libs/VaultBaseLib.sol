// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../core/libs/ConstantsLib.sol";
import "../../interfaces/IVault.sol";
import "../../interfaces/IControllable.sol";
import "../../interfaces/IPlatform.sol";
import "../../interfaces/IVaultManager.sol";
import "../../interfaces/IFactory.sol";
import "../../interfaces/IStrategyLogic.sol";

library VaultBaseLib {
    using SafeERC20 for IERC20;

    struct MintFeesVars {
        uint feePlatform;
        uint feeShareVaultManager;
        uint feeShareStrategyLogic;
        uint feeShareEcosystem;
        uint vaultSharesForPlatform;
        uint vaultSharesForVaultManager;
        uint vaultSharesForStrategyLogic;
        uint vaultSharesForEcosystem;
    }

    function hardWorkMintFeeCallback(
        IPlatform platform,
        address[] memory revenueAssets,
        uint[] memory revenueAmounts,
        IVault.VaultBaseStorage storage $
    ) external returns (address[] memory feeReceivers, uint[] memory feeShares) {
        MintFeesVars memory v;
        IStrategy s = $.strategy;
        if (address(s) != msg.sender) {
            revert IControllable.IncorrectMsgSender();
        }

        (, uint revenueSharesOut,) = IVault(address(this)).previewDepositAssets(revenueAssets, revenueAmounts);

        (v.feePlatform, v.feeShareVaultManager, v.feeShareStrategyLogic, v.feeShareEcosystem) = platform.getFees();
        try platform.getCustomVaultFee(address(this)) returns (uint vaultCustomFee) {
            if (vaultCustomFee != 0) {
                v.feePlatform = vaultCustomFee;
            }
        } catch {}
        uint strategyLogicTokenId =
            IFactory(platform.factory()).strategyLogicConfig(keccak256(bytes(s.strategyLogicId()))).tokenId;

        uint returnArraysLength = 2;
        v.vaultSharesForPlatform = revenueSharesOut * v.feePlatform / ConstantsLib.DENOMINATOR;
        v.vaultSharesForVaultManager = v.vaultSharesForPlatform * v.feeShareVaultManager / ConstantsLib.DENOMINATOR;
        v.vaultSharesForStrategyLogic = v.vaultSharesForPlatform * v.feeShareStrategyLogic / ConstantsLib.DENOMINATOR;
        if (v.feeShareEcosystem != 0) {
            v.vaultSharesForEcosystem = v.vaultSharesForPlatform * v.feeShareEcosystem / ConstantsLib.DENOMINATOR;
            ++returnArraysLength;
        }
        uint multisigShare =
            ConstantsLib.DENOMINATOR - v.feeShareVaultManager - v.feeShareStrategyLogic - v.feeShareEcosystem;
        uint vaultSharesForMultisig;
        if (multisigShare > 0) {
            vaultSharesForMultisig = v.vaultSharesForPlatform - v.vaultSharesForVaultManager
                - v.vaultSharesForStrategyLogic - v.vaultSharesForEcosystem;
            ++returnArraysLength;
        }
        feeReceivers = new address[](returnArraysLength);
        feeShares = new uint[](returnArraysLength);

        // vaultManagerReceiver
        feeReceivers[0] = IVaultManager(platform.vaultManager()).getRevenueReceiver($.tokenId);
        feeShares[0] = v.vaultSharesForVaultManager;
        // strategyLogicReceiver
        feeReceivers[1] = IStrategyLogic(platform.strategyLogic()).getRevenueReceiver(strategyLogicTokenId);
        feeShares[1] = v.vaultSharesForStrategyLogic;
        // ecosystem
        uint k = 2;
        if (v.vaultSharesForEcosystem != 0) {
            feeReceivers[k] = platform.ecosystemRevenueReceiver();
            feeShares[k] = v.vaultSharesForEcosystem;
            ++k;
        }
        if (vaultSharesForMultisig != 0) {
            feeReceivers[k] = platform.multisig();
            feeShares[k] = vaultSharesForMultisig;
        }
        emit IVault.MintFees(
            v.vaultSharesForVaultManager,
            v.vaultSharesForStrategyLogic,
            v.vaultSharesForEcosystem,
            vaultSharesForMultisig
        );
    }
}
