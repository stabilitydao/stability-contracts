// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IStabilityVault} from "./IStabilityVault.sol";

interface IMetaVault is IStabilityVault {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.MetaVault
    struct MetaVaultStorage {
        /// @inheritdoc IMetaVault
        address pegAsset;
        /// @inheritdoc IMetaVault
        EnumerableSet.AddressSet assets;
        /// @inheritdoc IMetaVault
        address[] vaults;
        address targetVault;
        /// @inheritdoc IMetaVault
        uint[] targetProportions;
        /// @inheritdoc IERC20Metadata
        string name;
        /// @inheritdoc IERC20Metadata
        string symbol;
        /// @inheritdoc IERC20
        mapping(address owner => mapping(address spender => uint allowance)) allowance;
        uint totalShares;
        mapping(address => uint) shareBalance;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Vault price pegged currency
    function pegAsset() external view returns (address);

    /// @notice Underlying assets
    function assets() external view returns (address[] memory);

    /// @notice Used CVaults
    function vaults() external view returns (address[] memory);

    /// @notice Current proportions of value between vaults
    /// @return Shares of 1e18
    function currentProportions() external view returns (uint[] memory);

    /// @notice Target proportions of value between vaults
    /// @return Shares of 1e18
    function targetProportions() external view returns (uint[] memory);

    /// @notice Vault where to deposit first
    function targetVault() external view returns (address);

    /// @notice Assets for deposit
    function targetAssets() external view returns (address[] memory);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Single asset re-balancing
    function rebalance(
        uint[] memory withdrawAmounts,
        uint[] memory depositAmounts
    ) external returns (uint proportions, uint cost);

    /// @notice Add CVault to MetaVault
    function addVault(address vault, uint[] memory newTargetProportions) external;

    /// @notice Init after deploy
    function initialize(
        address platform_,
        address pegAsset_,
        string memory name_,
        string memory symbol_,
        address[] memory vaults_,
        uint[] memory proportions_
    ) external;
}
