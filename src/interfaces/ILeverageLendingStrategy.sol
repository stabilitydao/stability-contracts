// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ILeverageLendingStrategy {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.LeverageLendingBase
    struct LeverageLendingBaseStorage {
        address collateralAsset;
        address borrowAsset;
        address lendingVault;
        address borrowingVault;
    }
}
