// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../interfaces/IAmmAdapter.sol";

/// @dev Liquidity providing strategy

interface ILPStrategy {
    event FeesClaimed(uint[] fees);

    error ZeroAmmAdapter();
    error IncorrectAssetsLength();
    error IncorrectAssets();
    error IncorrectAmountsLength();
    
    struct LPStrategyBaseInitParams {
        string id;
        address platform;
        address vault;
        address pool;
        address underlying;
    }

    /// @dev AMM adapter string ID for interacting with pool
    function ammAdapterId() external view returns(string memory);

    /// @dev AMM adapter address for interacting with pool
    function ammAdapter() external view returns (IAmmAdapter);

    /// @dev AMM
    function pool() external view returns (address);
}
