// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPlatform} from "../../interfaces/IPlatform.sol";
import {IPool} from "../../integrations/aave/IPool.sol";
import {ILeverageLendingStrategy} from "../../interfaces/ILeverageLendingStrategy.sol";
import {IControllable} from "../../interfaces/IControllable.sol";
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {IBVault} from "../../integrations/balancer/IBVault.sol";
import {IUniswapV3PoolActions} from "../../integrations/uniswapv3/pool/IUniswapV3PoolActions.sol";
import {IUniswapV3PoolImmutables} from "../../integrations/uniswapv3/pool/IUniswapV3PoolImmutables.sol";
import {IVaultMainV3} from "../../integrations/balancerv3/IVaultMainV3.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

library AaveLeverageToolLib {
    using SafeERC20 for IERC20;

    // keccak256(abi.encode(uint(keccak256("erc7201:stability.AaveLeverageTool")) - 1)) & ~bytes32(uint(0xff));
    bytes32 internal constant _LIQUIDATION_BOT_STORAGE_LOCATION = 0; // todo

    /// @dev 100_00 is 1.0 or 100%
    uint public constant INTERNAL_PRECISION = 100_00;

    //region -------------------------------------- Data types

    error UnauthorizedCallback();

    event SetFlashLoan(address vault, uint kind);

    /// @custom:storage-location erc7201:stability.AaveLeverageTool
    struct AaveLeverageToolStorage {
        /// @notice Address of the vault to take flash loans from (if needed).
        /// The type of vault is determined by the {flashLoanKind}
        address flashLoanVault;

        /// @notice Same values as in ILeverageLendingStrategy.FlashLoanKind flashLoanKind
        /// But some kinds can be not supported, see the code below
        uint flashLoanKind;

    }



    //endregion -------------------------------------- Data types

    //region -------------------------------------- Main actions

    //endregion -------------------------------------- Main actions


    //region -------------------------------------- Restricted actions
    /// @notice Set flash loan vault and kind
    function setFlashLoanVault(address flashLoanVault, uint flashLoanKind) internal {
        AaveLeverageToolStorage storage $ = getStorage();
        $.flashLoanKind = flashLoanKind;
        $.flashLoanVault = flashLoanVault;

        emit SetFlashLoan(flashLoanVault, flashLoanKind);
    }

    //endregion -------------------------------------- Restricted actions

    //region -------------------------------------- Flash loan

    /// @notice Get flash loan
    /// @dev This version of function passes {userData} to the callback
    function _requestFlashLoanExplicit(
        uint flashLoanKind,
        address flashLoanVault,
        address flashAsset_,
        uint flashAmount_,
        bytes memory userData
    ) internal {
        if (flashLoanKind == uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1)) {
            // --------------- Flash loan of Balancer v3, free. The strategy should support IBalancerV3FlashCallback
            // fee amount are always 0, flash loan in balancer v3 is free
            bytes memory data = abi.encodeWithSignature(
                "receiveFlashLoanV3(address,uint256,bytes)", flashAsset_, flashAmount_, userData
            );

            IVaultMainV3(payable(flashLoanVault)).unlock(data);
        } else {
            address[] memory flashAssets = new address[](1);
            flashAssets[0] = flashAsset_;
            uint[] memory flashAmounts = new uint[](1);
            flashAmounts[0] = flashAmount_;

            if (
                // assume here that Algebra uses exactly same API as UniswapV3
                flashLoanKind == uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2)
                || flashLoanKind == uint(ILeverageLendingStrategy.FlashLoanKind.AlgebraV4_3)
            ) {
                // --------------- Flash loan Uniswap V3. The strategy should support IUniswapV3FlashCallback
                // ensure that the vault has available amount
                require(
                    IERC20(flashAssets[0]).balanceOf(address(flashLoanVault)) >= flashAmounts[0],
                    IControllable.InsufficientBalance()
                );

                bool isToken0 = IUniswapV3PoolImmutables(flashLoanVault).token0() == flashAssets[0];
                IUniswapV3PoolActions(flashLoanVault).flash(
                    address(this),
                    isToken0 ? flashAmounts[0] : 0,
                    isToken0 ? 0 : flashAmounts[0],
                    abi.encode(flashAssets[0], flashAmounts[0], isToken0, userData)
                );
            } else {
                // --------------- Default flash loan Balancer v2, paid. The strategy should support IFlashLoanRecipient
                IBVault(flashLoanVault).flashLoan(address(this), flashAssets, flashAmounts, userData);
            }
        }
    }

    /// @notice Process received flash loan
    /// @param token Address of the token received in flash loan. This is the debt asset.
    /// @param amount Amount of the token received in flash loan = a part of the user debt to be paid in liquidation
    /// @param fee Fee of the flash loan (if any)
    /// @param userData User data passed to the callback
    function receiveFlashLoan(
        address platform,
        AaveLeverageToolStorage storage $,
        address token,
        uint amount,
        uint fee,
        bytes memory userData
    ) internal {
        address flashLoanVault = $.flashLoanVault;
        require(msg.sender == flashLoanVault, UnauthorizedCallback());

        // todo
    }
    //endregion -------------------------------------- Flash loan


    //region -------------------------------------- Utils
    function getStorage() internal pure returns (AaveLeverageToolStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := _LIQUIDATION_BOT_STORAGE_LOCATION
        }
    }
    //endregion -------------------------------------- Utils
}