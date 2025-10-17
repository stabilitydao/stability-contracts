// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface IRevenueRouter {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event EpochFlip(uint periodEnded, uint totalStblRevenue);
    event AddedUnit(uint unitIndex, UnitType unitType, string name, address feeTreasury);
    event UpdatedUnit(uint unitIndex, UnitType unitType, string name, address feeTreasury);
    event UnitEpochRevenue(uint periodEnded, string unitName, uint stblRevenue);
    event ProcessUnitRevenue(uint unitIndex, uint stblGot);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CUSTOM ERRORS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error WaitForNewPeriod();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.RevenueRouter
    struct RevenueRouterStorage {
        address stbl;
        address xStbl;
        address xStaking;
        address feeTreasury;
        uint xShare;
        uint activePeriod;
        uint pendingRevenue;
        Unit[] units;
        address[] aavePools;
        EnumerableSet.AddressSet vaultsAccumulated;
    }

    enum UnitType {
        Core,
        AaveMarkets,
        Assets
    }

    struct Unit {
        UnitType unitType;
        string name;
        uint pendingRevenue;
        address feeTreasury;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        GOV ACTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Add new Unit
    function addUnit(UnitType unitType, string calldata name, address feeTreasury) external;

    /// @notice Update Unit
    function updateUnit(uint unitIndex, UnitType unitType, string calldata name, address feeTreasury) external;

    /// @notice Setup Aave pool list
    function setAavePools(address[] calldata pools) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       USER ACTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Update the epoch (period) -- callable once a week at >= Thursday 0 UTC
    /// @return newPeriod The new period
    function updatePeriod() external returns (uint newPeriod);

    /// @notice Process platform fee in form of an asset
    function processFeeAsset(address asset, uint amount) external;

    /// @notice Process platform fee in form of an vault shares
    function processFeeVault(address vault, uint amount) external;

    /// @notice Claim unit fees and swap to STBL
    function processUnitRevenue(uint unitIndex) external;

    /// @notice Claim units fees and swap to STBL
    function processUnitsRevenue() external;

    /// @notice Withdraw assets from accumulated vaults and swap to STBL
    function processAccumulatedVaults(uint maxVaultsForWithdraw) external;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Show all Units
    function units() external view returns (Unit[] memory);

    /// @notice The period used for rewarding
    /// @return The block.timestamp divided by 1 week in seconds
    function getPeriod() external view returns (uint);

    /// @notice Current active period
    function activePeriod() external view returns (uint);

    /// @notice Accumulated STBL amount for next distribution by core unit (vault fees)
    function pendingRevenue() external view returns (uint);

    /// @notice Accumulated STBL amount for next distribution by unit
    function pendingRevenue(uint unitIndex) external view returns (uint);

    /// @notice Get Aave pool list to mintToTreasury calls
    function aavePools() external view returns (address[] memory);

    /// @notice Get vault addresses that contract hold on balance, but not withdrew yet
    function vaultsAccumulated() external view returns (address[] memory);

    /// @notice Addresses of STBL, xSTBL, xStaking and feeTreasure token
    function addresses() external view returns (address[] memory);
}
