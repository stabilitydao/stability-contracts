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
        /// @dev Flash loan exploit protection.
        ///      Prevents manipulations with deposit/transfer and withdraw/deposit in short time.
        mapping(address msgSender => uint blockNumber) lastTransferBlock;
        /// @dev Immutable vault type ID
        string _type;
        /// @inheritdoc IMetaVault
        address pegAsset;
        /// @inheritdoc IMetaVault
        EnumerableSet.AddressSet assets;
        /// @inheritdoc IMetaVault
        address[] vaults;
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
        uint storedSharePrice;
        uint storedTime;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event APR(uint sharePrice, int apr, uint lastStoredSharePrice, uint duration);
    event AddVault(address vault);
    event TargetProportions(uint[] proportions);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error UsdAmountLessThreshold(uint amountUsd, uint threshold);
    error MaxAmountForWithdrawPerTxReached(uint amount, uint maxAmount);
    error ZeroSharesToBurn(uint amountToWithdraw);
    error IncorrectProportions();
    error IncorrectVault();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Not perform operations with value less than threshold
    function USD_THRESHOLD() external view returns (uint);

    /// @notice Vault price pegged currency
    function pegAsset() external view returns (address);

    /// @notice Used CVaults
    function vaults() external view returns (address[] memory);

    /// @notice Current proportions of value between vaults
    /// @return Shares of 1e18
    function currentProportions() external view returns (uint[] memory);

    /// @notice Target proportions of value between vaults
    /// @return Shares of 1e18
    function targetProportions() external view returns (uint[] memory);

    /// @notice Vault where to deposit first
    function vaultForDeposit() external view returns (address);

    /// @notice Assets for deposit
    function assetsForDeposit() external view returns (address[] memory);

    /// @notice Vault for withdraw first
    function vaultForWithdraw() external view returns (address);

    /// @notice Assets for withdraw
    function assetsForWithdraw() external view returns (address[] memory);

    /// @notice Maximum withdraw amount for next withdraw TX
    function maxWithdrawAmountTx() external view returns (uint);

    /// @notice Show internal share prices
    /// @return sharePrice Current internal share price
    /// @return apr Current APR
    /// @return storedSharePrice Stored internal share price
    /// @return storedTime Time when stored
    function internalSharePrice()
        external
        view
        returns (uint sharePrice, int apr, uint storedSharePrice, uint storedTime);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Update stored internal share price and emit APR
    /// @return sharePrice Current internal share price
    /// @return apr APR for last period
    /// @return lastStoredSharePrice Last stored internal share price
    /// @return duration Duration of last tracked period
    function emitAPR() external returns (uint sharePrice, int apr, uint lastStoredSharePrice, uint duration);

    /// @notice Single asset re-balancing
    function rebalance(
        uint[] memory withdrawAmounts,
        uint[] memory depositAmounts
    ) external returns (uint proportions, uint cost);

    /// @notice Set new target proportions
    function setTargetProportions(uint[] memory newTargetProportions) external;

    /// @notice Add CVault to MetaVault
    function addVault(address vault, uint[] memory newTargetProportions) external;

    /// @notice Init after deploy
    function initialize(
        address platform_,
        string memory type_,
        address pegAsset_,
        string memory name_,
        string memory symbol_,
        address[] memory vaults_,
        uint[] memory proportions_
    ) external;
}
