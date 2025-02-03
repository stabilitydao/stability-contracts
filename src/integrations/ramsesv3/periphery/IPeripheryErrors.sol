// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

/// @title Errors emitted by the NonFungiblePositionManager
/// @notice Contains all events emitted by the NfpManager
interface IPeripheryErrors {
    error InvalidTokenId(uint tokenId);
    error CheckSlippage();
    error NotCleared();
}
