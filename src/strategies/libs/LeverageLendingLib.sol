// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IBVault} from "../../integrations/balancer/IBVault.sol";
import {IBComposableStablePoolMinimal} from "../../integrations/balancer/IBComposableStablePoolMinimal.sol";
import {IControllable} from "../../interfaces/IControllable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ILeverageLendingStrategy} from "../../interfaces/ILeverageLendingStrategy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVaultMainV3} from "../../integrations/balancerv3/IVaultMainV3.sol";
import {IUniswapV3PoolActions} from "../../integrations/uniswapv3/pool/IUniswapV3PoolActions.sol";
import {IUniswapV3PoolImmutables} from "../../integrations/uniswapv3/pool/IUniswapV3PoolImmutables.sol";

/// @notice Shared functions for Leverage Lending strategies
library LeverageLendingLib {
    using SafeERC20 for IERC20;

    uint internal constant PRICE_IMPACT_DENOMINATOR = 100_000;

    /// @dev Get flash loan. Proper callback will be called in the strategy (depends on the kind of the flash loan)
    function requestFlashLoan(
        ILeverageLendingStrategy.LeverageLendingBaseStorage storage $,
        address[] memory flashAssets,
        uint[] memory flashAmounts
    ) internal {
        return requestFlashLoanExplicit(
            ILeverageLendingStrategy.FlashLoanKind($.flashLoanKind), $.flashLoanVault, flashAssets, flashAmounts
        );
    }

    /// @dev Allow to specify vault explicitly, i.e. in SiL where borrow asset is taken from different flash loan vault
    function requestFlashLoanExplicit(
        ILeverageLendingStrategy.FlashLoanKind flashLoanKind,
        address flashLoanVault,
        address[] memory flashAssets,
        uint[] memory flashAmounts
    ) internal {
        if (flashLoanKind == ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1) {
            // --------------- Flash loan of Balancer v3, free. The strategy should support IBalancerV3FlashCallback
            // fee amount are always 0, flash loan in balancer v3 is free
            bytes memory data = abi.encodeWithSignature(
                "receiveFlashLoanV3(address,uint256,bytes)",
                flashAssets[0],
                flashAmounts[0],
                bytes("") // no user data
            );

            IVaultMainV3(payable(flashLoanVault)).unlock(data);
        } else if (
            // assume here that Algebra uses exactly same API as UniswapV3
            flashLoanKind == ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2
                || flashLoanKind == ILeverageLendingStrategy.FlashLoanKind.AlgebraV4_3
        ) {
            // --------------- Flash loan Uniswap V3. The strategy should support IUniswapV3FlashCallback
            // ensure that the vault has available amount
            require(
                IERC20(flashAssets[0]).balanceOf(address(flashLoanVault)) >= flashAmounts[0],
                IControllable.InsufficientBalance()
            );

            bool isToken0 = IUniswapV3PoolImmutables(flashLoanVault).token0() == flashAssets[0];
            IUniswapV3PoolActions(flashLoanVault)
                .flash(
                    address(this),
                    isToken0 ? flashAmounts[0] : 0,
                    isToken0 ? 0 : flashAmounts[0],
                    abi.encode(flashAssets[0], flashAmounts[0], isToken0)
                );
        } else {
            // --------------- Default flash loan Balancer v2, paid. The strategy should support IFlashLoanRecipient
            IBVault(flashLoanVault).flashLoan(address(this), flashAssets, flashAmounts, "");
        }
    }

    /// @notice Get flash loan fee, decimals 18
    function getFlashFee18(address flashLoanVault, uint flashLoanKind) internal view returns (uint) {
        if (flashLoanKind == uint(ILeverageLendingStrategy.FlashLoanKind.Default_0)) {
            return IBComposableStablePoolMinimal(flashLoanVault).getSwapFeePercentage(); // decimals 18
        } else if (flashLoanKind == uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1)) {
            // flash loan in balancer v3 is free
            return 0;
        } else if (
            flashLoanKind == uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2)
            || flashLoanKind == uint(ILeverageLendingStrategy.FlashLoanKind.AlgebraV4_3)
        ) {
            // fee is in hundredths of a bip, i.e. 100_00 = 1%
            return uint(IUniswapV3PoolImmutables(flashLoanVault).fee()) * 1e12;
        }
        return 0; // unknown
    }

}
