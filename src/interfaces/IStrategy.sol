// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @dev Main strategy interface
interface IStrategy {
    /// @dev A single universal initializer for all strategy implementations.
    /// @param addresses All addresses that strategy requires for initialization. Min array length is 2.
    ///        addresses[0]: platform (required)
    ///        addresses[1]: vault (required)
    ///        addresses[2]: initStrategyAddresses[0] (optional)
    ///        addresses[3]: initStrategyAddresses[1] (optional)
    ///        addresses[n]: initStrategyAddresses[n - 2] (optional)
    /// @param nums All uint values that strategy requires for initialization. Min array length is 0.
    /// @param ticks All int24 values that strategy requires for initialization. Min array length is 0.
    function initialize(
        address[] memory addresses,
        uint[] memory nums,
        int24[] memory ticks
    ) external;

    /// @dev Strategy logic string ID
    function STRATEGY_LOGIC_ID() external view returns(string memory);

    /// @dev Extra data
    /// @return 0-2 bytes - strategy color
    ///         3-5 bytes - strategy background color
    ///         6-31 bytes - free
    function extra() external view returns (bytes32);

    /// @dev Types of vault that supported by strategy implementation
    function supportedVaultTypes() external view returns(string[] memory types);

    /// @dev Linked vault address
    function vault() external view returns (address);

    /// @dev Final assets that strategy invests
    function assets() external view returns (address[] memory);

    function assetsAmounts() external view returns (address[] memory assets_, uint[] memory amounts_);

    function getAssetsProportions() external view returns (uint[] memory proportions);

    /// @dev Can be used for liquidity farming strategies where AMM has fungible liquidity token (Solidly forks, etc),
    ///      for concentrated liquidity tokenized vaults (Gamma, G-UNI etc) and for other needs.
    function underlying() external view returns (address);

    /// @dev Balance of liquidity token or liquidity value
    function total() external view returns (uint);

    /// @dev Last hard work timestamp
    function lastHardWork() external view returns (uint);

    /// @dev Last APR of earned USD amount registered by HardWork
    ///      ONLY FOR OFF-CHAIN USE.
    ///      Not trusted asset price can be manipulated.
    function lastApr() external view returns (uint);

    /// @dev Last APR of compounded assets registered by HardWork.
    ///      Can be used on-chain.
    function lastAprCompound() external view returns (uint);

    function previewDepositAssets(address[] memory assets_, uint[] memory amountsMax) external view returns (uint[] memory amountsConsumed, uint value);

    function getRevenue() external view returns (address[] memory __assets, uint[] memory amounts);

    function getSpecificName() external view returns (string memory);

    /// @param platform_ Need this param because method called when strategy implementation is not initialized
    function initVariants(address platform_) external view returns (string[] memory variants, address[] memory addresses, uint[] memory nums, int24[] memory ticks);

    /// @dev Invest strategy assets. Amounts of assets must be already on strategy contract balance.
    function depositAssets(uint[] memory amounts) external returns(uint value);

    function depositUnderlying(uint amount) external returns(uint[] memory amountsConsumed);

    /// @dev For specified amount of shares and assets_, withdraw strategy assets from farm/pool/staking and send to receiver if possible
    ///      Only vault of strategy allowed to call this method
    /// @param assets_ Here we give the user a choice of assets to withdraw if strategy support it
    /// @param value Part of strategy total value to withdraw
    function withdrawAssets(address[] memory assets_, uint value, address receiver) external returns (uint[] memory amountsOut);

    function withdrawUnderlying(uint amount, address receiver) external;

    /// @dev For specified amount of shares, transfer strategy assets from contract balance and send to receiver if possible
    ///      Only vault of strategy allowed to call this method
    function transferAssets(uint amount, uint total, address receiver) external returns (uint[] memory amountsOut);

    function doHardWork() external;
}
