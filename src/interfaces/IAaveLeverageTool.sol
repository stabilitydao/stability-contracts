// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAaveLeverageTool {
    //region ----------------------------------- View functions
    function getFlashLoanVault() external view returns (address flashLoanVault, uint flashLoanKind);


    //endregion ----------------------------------- View functions

    //region ----------------------------------- Write functions
    function setFlashLoanVault(address flashLoanVault, uint flashLoanKind) external;

    /// @dev Init
    function initialize(address platform_) external;
    //endregion ----------------------------------- Write functions
}