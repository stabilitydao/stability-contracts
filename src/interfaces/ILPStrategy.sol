// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../interfaces/IAmmAdapter.sol";

/// @title Liquidity providing strategy
/// @author Alien Deployer (https://github.com/a17)
interface ILPStrategy {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event FeesClaimed(uint[] fees);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error ZeroAmmAdapter();
    error IncorrectAssetsLength();
    error IncorrectAssets();
    error IncorrectAmountsLength();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.LPStrategyBase
    struct LPStrategyBaseStorage {
        /// @inheritdoc ILPStrategy
        address pool;
        /// @inheritdoc ILPStrategy
        IAmmAdapter ammAdapter;
        uint[] _feesOnBalance;
    }

    struct LPStrategyBaseInitParams {
        string id;
        address platform;
        address vault;
        address pool;
        address underlying;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev AMM adapter string ID for interacting with pool
    function ammAdapterId() external view returns (string memory);

    /// @dev AMM adapter address for interacting with pool
    function ammAdapter() external view returns (IAmmAdapter);

    /// @dev AMM
    function pool() external view returns (address);
}
