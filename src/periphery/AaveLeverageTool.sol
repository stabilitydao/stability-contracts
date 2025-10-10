// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AaveLeverageToolLib} from "./libs/AaveLeverageToolLib.sol";
import {Controllable, IControllable, IPlatform} from "../core/base/Controllable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IAaveLeverageTool} from "../interfaces/IAaveLeverageTool.sol";
import {IAlgebraFlashCallback} from "../integrations/algebrav4/callback/IAlgebraFlashCallback.sol";
import {IBalancerV3FlashCallback} from "../integrations/balancerv3/IBalancerV3FlashCallback.sol";
import {IFlashLoanRecipient} from "../integrations/balancer/IFlashLoanRecipient.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";
import {IUniswapV3FlashCallback} from "../integrations/uniswapv3/IUniswapV3FlashCallback.sol";

/// @title Create leveraged position on lending market AAVE v3.0.2
/// @author dvpublic (https://github.com/dvpublic)
/// Changelog:
contract AaveLeverageTool is
    Controllable,
    IAaveLeverageTool,
    IFlashLoanRecipient,
    IUniswapV3FlashCallback,
    IBalancerV3FlashCallback,
    IAlgebraFlashCallback
{
    using EnumerableSet for EnumerableSet.AddressSet;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IAaveLeverageTool
    function initialize(address platform_) public initializer {
        __Controllable_init(platform_);
    }

    //region ----------------------------------- View
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @inheritdoc IAaveLeverageTool
    function getFlashLoanVault() external view returns (address flashLoanVault, uint flashLoanKind) {
        AaveLeverageToolLib.AaveLeverageToolStorage storage $ = AaveLeverageToolLib.getStorage();
        return ($.flashLoanVault, $.flashLoanKind);
    }

    //endregion ----------------------------------- View

    //region ----------------------------------- Flash loan
    /// @inheritdoc IFlashLoanRecipient
    /// @dev Support of FLASH_LOAN_KIND_BALANCER_V2
    function receiveFlashLoan(
        address[] memory tokens,
        uint[] memory amounts,
        uint[] memory feeAmounts,
        bytes memory userData
    ) external {
        // Flash loan is performed upon deposit and withdrawal
        AaveLeverageToolLib.AaveLeverageToolStorage storage $ = AaveLeverageToolLib.getStorage();
        AaveLeverageToolLib.receiveFlashLoan(platform(), $, tokens[0], amounts[0], feeAmounts[0], userData);
    }

    /// @inheritdoc IBalancerV3FlashCallback
    function receiveFlashLoanV3(address token, uint amount, bytes memory userData) external {
        // sender is vault, it's checked inside receiveFlashLoan
        // we can use msg.sender below but $.flashLoanVault looks more safe
        AaveLeverageToolLib.AaveLeverageToolStorage storage $ = AaveLeverageToolLib.getStorage();
        IVaultMainV3 vault = IVaultMainV3(payable($.flashLoanVault));

        // ensure that the vault has available amount
        require(IERC20(token).balanceOf(address(vault)) >= amount, IControllable.InsufficientBalance());

        // receive flash loan from the vault
        vault.sendTo(token, address(this), amount);

        // Flash loan is performed upon deposit and withdrawal
        AaveLeverageToolLib.receiveFlashLoan(platform(), $, token, amount, 0, userData); // assume that flash loan is free, fee is 0

        // return flash loan back to the vault
        // assume that the amount was transferred back to the vault inside receiveFlashLoan()
        // we need only to register this transferring
        //slither-disable-next-line unused-return
        vault.settle(token, amount);
    }

    /// @inheritdoc IUniswapV3FlashCallback
    function uniswapV3FlashCallback(uint fee0, uint fee1, bytes calldata userData) external {
        // sender is the pool, it's checked inside receiveFlashLoan
        (address token, uint amount, bool isToken0, bytes memory data) =
                            abi.decode(userData, (address, uint, bool, bytes));

        AaveLeverageToolLib.AaveLeverageToolStorage storage $ = AaveLeverageToolLib.getStorage();
        AaveLeverageToolLib.receiveFlashLoan(platform(), $, token, amount, isToken0 ? fee0 : fee1, data);
    }

    function algebraFlashCallback(uint fee0, uint fee1, bytes calldata userData) external {
        // sender is the pool, it's checked inside receiveFlashLoan
        (address token, uint amount, bool isToken0, bytes memory data) =
                            abi.decode(userData, (address, uint, bool, bytes));

        AaveLeverageToolLib.AaveLeverageToolStorage storage $ = AaveLeverageToolLib.getStorage();
        AaveLeverageToolLib.receiveFlashLoan(platform(), $, token, amount, isToken0 ? fee0 : fee1, data);
    }
    //endregion ----------------------------------- Flash loan

    //region ----------------------------------- Restricted actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
    /// @inheritdoc IAaveLeverageTool
    function setFlashLoanVault(address flashLoanVault, uint flashLoanKind) external onlyMultisig {
        AaveLeverageToolLib.setFlashLoanVault(flashLoanVault, flashLoanKind);
    }

    //endregion ----------------------------------- Restricted actions

    //region ----------------------------------- Actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      Actions                               */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/


    //endregion ----------------------------------- Actions
}
