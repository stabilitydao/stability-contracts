// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnumerableMap, EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

interface IRevenueRouter {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event EpochFlip(uint periodEnded, uint totalStblRevenue);
    event AddedUnit(uint unitIndex, UnitType unitType, string name, address feeTreasury);
    event UpdatedUnit(uint unitIndex, UnitType unitType, string name, address feeTreasury);
    event UnitEpochRevenue(uint periodEnded, string unitName, uint stblRevenue);
    event ProcessUnitRevenue(uint unitIndex, uint stblGot);
    event SetAddresses(address[] addresses);
    event BuyBackRate(uint bbRate);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                        CUSTOM ERRORS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error WaitForNewPeriod();
    error IncorrectSetup();
    error CantProcessAction();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.RevenueRouter
    struct RevenueRouterStorage {
        address token;
        address xToken;
        address xStaking;
        address feeTreasury;
        uint __deprecated_xShare;
        uint activePeriod;
        uint pendingRevenue;
        Unit[] units;
        address[] aavePools;
        EnumerableSet.AddressSet vaultsAccumulated;
        EnumerableSet.AddressSet assetsAccumulated;
        EnumerableMap.AddressToUintMap minSwapAmount;
        EnumerableMap.AddressToUintMap maxSwapAmount;

        // todo use DAO parameter
        uint bbRate;
        EnumerableMap.AddressToUintMap pendingRevenueAsset;
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

    /// @notice Set min swap amounts for assets
    function setMinSwapAmounts(address[] calldata assets, uint[] calldata minAmounts) external;

    /// @notice Set max swap amounts for assets
    function setMaxSwapAmounts(address[] calldata assets, uint[] calldata maxAmounts) external;

    /// @notice Set addresses of main-token, xToken, xStaking and feeTreasure token.
    function setAddresses(address[] memory addresses_) external;

    /// @notice Set buy-back rate for rewards
    function setBuyBackRate(uint bbRate) external;

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

    /// @notice Claim unit fees and swap to main-token
    function processUnitRevenue(uint unitIndex) external;

    /// @notice Claim units fees and swap to main-token (STBL)
    function processUnitsRevenue() external;

    /// @notice Withdraw assets from accumulated vaults (STBL)
    function processAccumulatedVaults(uint maxVaultsForWithdraw) external;

    /// @notice Withdraw assets from accumulated vaults
    function processAccumulatedVaults(uint maxVaultsForWithdraw, uint maxWithdrawAmount) external;

    /// @notice Distribute extracted accumulated assets amounts
    function processAccumulatedAssets(uint maxAssetsForProcess) external;

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

    /// @notice Accumulated main-token amount for next distribution by core unit (vault fees)
    function pendingRevenue() external view returns (uint);

    /// @notice Accumulated main-token amount for next distribution by unit
    function pendingRevenue(uint unitIndex) external view returns (uint);

    /// @notice Get Aave pool list to mintToTreasury calls
    function aavePools() external view returns (address[] memory);

    /// @notice Get vault addresses that contract hold on balance, but not withdrew yet
    function vaultsAccumulated() external view returns (address[] memory);

    /// @notice Addresses of main-token, xToken, xStaking and feeTreasure token
    function addresses() external view returns (address[] memory);

    /// @notice Get assets that contract hold on balance
    function assetsAccumulated() external view returns (address[] memory);

    /// @notice Buy-back rate for generated revenue
    function buyBackRate() external view returns (uint);

    /// @notice Asset with pending revenue for distribution
    function pendingRevenueAssets() external view returns (address[] memory);

    /// @notice Pending revenue in form of asset
    /// @param asset Allowed asset address
    function pendingRevenueAsset(address asset) external view returns (uint);
}
