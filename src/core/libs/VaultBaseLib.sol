// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ConstantsLib} from "../../core/libs/ConstantsLib.sol";
import {IVault} from "../../interfaces/IVault.sol";
import {IControllable} from "../../interfaces/IControllable.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IStrategy} from "../../interfaces/IStrategy.sol";

library VaultBaseLib {
    using SafeERC20 for IERC20;

    struct MintFeesVars {
        uint feePlatform;
    }

    function hardWorkMintFeeCallback(
        IPlatform platform,
        address[] memory revenueAssets,
        uint[] memory revenueAmounts,
        IVault.VaultBaseStorage storage $
    ) external view returns (uint feeShares) {
        MintFeesVars memory v;
        IStrategy s = $.strategy;
        if (address(s) != msg.sender) {
            revert IControllable.IncorrectMsgSender();
        }

        (, uint revenueSharesOut,) = IVault(address(this)).previewDepositAssets(revenueAssets, revenueAmounts);

        (v.feePlatform,,,) = platform.getFees();
        try platform.getCustomVaultFee(address(this)) returns (uint vaultCustomFee) {
            if (vaultCustomFee != 0) {
                v.feePlatform = vaultCustomFee;
            }
        } catch {}

        feeShares = revenueSharesOut * v.feePlatform / ConstantsLib.DENOMINATOR;
    }
}
