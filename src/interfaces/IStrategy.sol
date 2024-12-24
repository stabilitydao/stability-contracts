// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @dev Core interface of strategy logic
interface IStrategy is IERC165 {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event HardWork(
        uint apr, uint compoundApr, uint earned, uint tvl, uint duration, uint sharePrice, uint[] assetPrices
    );
    event ExtractFees(
        uint vaultManagerReceiverFee,
        uint strategyLogicReceiverFee,
        uint ecosystemRevenueReceiverFee,
        uint multisigReceiverFee
    );

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error NotReadyForHardWork();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.StrategyBase
    struct StrategyBaseStorage {
        /// @inheritdoc IStrategy
        address vault;
        /// @inheritdoc IStrategy
        uint total;
        /// @inheritdoc IStrategy
        uint lastHardWork;
        /// @inheritdoc IStrategy
        uint lastApr;
        /// @inheritdoc IStrategy
        uint lastAprCompound;
        /// @inheritdoc IStrategy
        address[] _assets;
        /// @inheritdoc IStrategy
        address _underlying;
        string _id;
        uint _exchangeAssetIndex;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Strategy logic string ID
    function strategyLogicId() external view returns (string memory);

    /// @dev Extra data
    /// @return 0-2 bytes - strategy color
    ///         3-5 bytes - strategy background color
    ///         6-31 bytes - free
    function extra() external view returns (bytes32);

    /// @dev Types of vault that supported by strategy implementation
    /// @return types Vault type ID strings
    function supportedVaultTypes() external view returns (string[] memory types);

    /// @dev Linked vault address
    function vault() external view returns (address);

    /// @dev Final assets that strategy invests
    function assets() external view returns (address[] memory);

    /// @notice Final assets and amounts that strategy manages
    function assetsAmounts() external view returns (address[] memory assets_, uint[] memory amounts_);

    /// @notice Priced invested assets proportions
    /// @return proportions Proportions of assets with 18 decimals. Min is 0, max is 1e18.
    function getAssetsProportions() external view returns (uint[] memory proportions);

    /// @notice Underlying token address
    /// @dev Can be used for liquidity farming strategies where AMM has fungible liquidity token (Solidly forks, etc),
    ///      for concentrated liquidity tokenized vaults (Gamma, G-UNI etc) and for other needs.
    /// @return Address of underlying token or zero address if no underlying in strategy
    function underlying() external view returns (address);

    /// @dev Balance of liquidity token or liquidity value
    function total() external view returns (uint);

    /// @dev Last HardWork time
    /// @return Timestamp
    function lastHardWork() external view returns (uint);

    /// @dev Last APR of earned USD amount registered by HardWork
    ///      ONLY FOR OFF-CHAIN USE.
    ///      Not trusted asset price can be manipulated.
    /// @return APR with 18 decimals. 1e18 - 100%.
    function lastApr() external view returns (uint);

    /// @dev Last APR of compounded assets registered by HardWork.
    ///      Can be used on-chain.
    /// @return APR with 18 decimals. 1e18 - 100%.
    function lastAprCompound() external view returns (uint);

    /// @notice Calculation of consumed amounts and liquidity/underlying value for provided strategy assets and amounts.
    /// @param assets_ Strategy assets or part of them, if necessary
    /// @param amountsMax Amounts of specified assets available for investing
    /// @return amountsConsumed Cosumed amounts of assets when investing
    /// @return value Liquidity value or underlying token amount minted when investing
    function previewDepositAssets(
        address[] memory assets_,
        uint[] memory amountsMax
    ) external view returns (uint[] memory amountsConsumed, uint value);

    /// @notice Write version of previewDepositAssets
    /// @param assets_ Strategy assets or part of them, if necessary
    /// @param amountsMax Amounts of specified assets available for investing
    /// @return amountsConsumed Cosumed amounts of assets when investing
    /// @return value Liquidity value or underlying token amount minted when investing
    function previewDepositAssetsWrite(
        address[] memory assets_,
        uint[] memory amountsMax
    ) external returns (uint[] memory amountsConsumed, uint value);

    /// @notice All strategy revenue (pool fees, farm rewards etc) that not claimed by strategy yet
    /// @return assets_ Revenue assets
    /// @return amounts Amounts. Index of asset same as in previous array.
    function getRevenue() external view returns (address[] memory assets_, uint[] memory amounts);

    /// @notice Optional specific name of investing strategy, underyling type, setup variation etc
    /// @return name Empty string or specific name
    /// @return showInVaultSymbol Show specific in linked vault symbol
    function getSpecificName() external view returns (string memory name, bool showInVaultSymbol);

    /// @notice Variants pf strategy initializations with description of money making mechanic.
    /// As example, if strategy need farm, then number of variations is number of available farms.
    /// If CAMM strategy have set of available widths (tick ranges), then number of variations is number of available farms.
    /// If both example conditions are met then total number or variations = total farms * total widths.
    /// @param platform_ Need this param because method called when strategy implementation is not initialized
    /// @return variants Descriptions of the strategy for making money
    /// @return addresses Init strategy addresses. Indexes for each variants depends of copmpared arrays lengths.
    /// @return nums Init strategy numbers. Indexes for each variants depends of copmpared arrays lengths.
    /// @return ticks Init strategy ticks. Indexes for each variants depends of copmpared arrays lengths.
    function initVariants(address platform_)
        external
        view
        returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks);

    /// @notice How does the strategy make money?
    /// @return Description in free form
    function description() external view returns (string memory);

    /// @notice Is HardWork on vault deposits can be enabled
    function isHardWorkOnDepositAllowed() external view returns (bool);

    /// @notice Is HardWork can be executed
    function isReadyForHardWork() external view returns (bool);

    /// @notice Strategy not need to process revenue on HardWorks
    function autoCompoundingByUnderlyingProtocol() external view returns (bool);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev A single universal initializer for all strategy implementations.
    /// @param addresses All addresses that strategy requires for initialization. Min array length is 2.
    ///        addresses[0]: platform (required)
    ///        addresses[1]: vault (required)
    ///        addresses[2]: initStrategyAddresses[0] (optional)
    ///        addresses[3]: initStrategyAddresses[1] (optional)
    ///        addresses[n]: initStrategyAddresses[n - 2] (optional)
    /// @param nums All uint values that strategy requires for initialization. Min array length is 0.
    /// @param ticks All int24 values that strategy requires for initialization. Min array length is 0.
    function initialize(address[] memory addresses, uint[] memory nums, int24[] memory ticks) external;

    /// @notice Invest strategy assets. Amounts of assets must be already on strategy contract balance.
    /// Only vault can call this.
    /// @param amounts Anounts of strategy assets
    /// @return value Liquidity value or underlying token amount
    function depositAssets(uint[] memory amounts) external returns (uint value);

    /// @notice Invest underlying asset. Asset must be already on strategy contract balance.
    /// Only vault can call this.
    /// @param amount Amount of underlying asset to invest
    /// @return amountsConsumed Cosumed amounts of invested assets
    function depositUnderlying(uint amount) external returns (uint[] memory amountsConsumed);

    /// @dev For specified amount of shares and assets_, withdraw strategy assets from farm/pool/staking and send to receiver if possible
    /// Only vault can call this.
    /// @param assets_ Here we give the user a choice of assets to withdraw if strategy support it
    /// @param value Part of strategy total value to withdraw
    /// @param receiver User address
    /// @return amountsOut Amounts of assets sent to user
    function withdrawAssets(
        address[] memory assets_,
        uint value,
        address receiver
    ) external returns (uint[] memory amountsOut);

    /// @notice Wothdraw underlying invested and send to receiver
    /// Only vault can call this.
    /// @param amount Ampunt of underlying asset to withdraw
    /// @param receiver User of vault which withdraw underlying from the vault
    function withdrawUnderlying(uint amount, address receiver) external;

    /// @dev For specified amount of shares, transfer strategy assets from contract balance and send to receiver if possible
    /// This method is called by vault w/o underlying on triggered fuse mode.
    /// Only vault can call this.
    /// @param amount Ampunt of liquidity value that user withdraw
    /// @param totalAmount Total amount of strategy liquidity
    /// @param receiver User of vault which withdraw assets
    /// @return amountsOut Amounts of strategy assets sent to user
    function transferAssets(
        uint amount,
        uint totalAmount,
        address receiver
    ) external returns (uint[] memory amountsOut);

    /// @notice Execute HardWork
    /// During HardWork strategy claiming revenue and processing it.
    /// Only vault can call this.
    function doHardWork() external;

    /// @notice Emergency stop investing by strategy, withdraw liquidity without rewards.
    /// This action triggers FUSE mode.
    /// Only governance or multisig can call this.
    function emergencyStopInvesting() external;
}
