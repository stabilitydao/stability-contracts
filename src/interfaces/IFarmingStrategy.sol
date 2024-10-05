// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @dev Mostly this interface need for front-end and tests for interacting with farming strategies
/// @author JodsMigel (https://github.com/JodsMigel)
interface IFarmingStrategy {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event RewardsClaimed(uint[] amounts);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           ERRORS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error BadFarm();
    error IncorrectStrategyId();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.FarmingStrategyBase
    struct FarmingStrategyBaseStorage {
        /// @inheritdoc IFarmingStrategy
        uint farmId;
        address[] _rewardAssets;
        uint[] _rewardsOnBalance;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Index of the farm used by initialized strategy
    function farmId() external view returns (uint);

    /// @notice Strategy can earn money on farm now
    /// Some strategies can continue work and earn pool fees after ending of farm rewards.
    function canFarm() external view returns (bool);

    /// @notice Mechanics of receiving farming rewards
    function farmMechanics() external view returns (string memory);

    /// @notice Farming reward assets for claim and liquidate
    /// @return Addresses of farm reward ERC20 tokens
    function farmingAssets() external view returns (address[] memory);

    /// @notice Address of pool for staking asset/underlying
    function stakingPool() external view returns (address);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Update strategy farming reward assets from Factory
    /// Only operator can call this
    function refreshFarmingAssets() external;
}
