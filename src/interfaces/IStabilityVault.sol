// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @notice Base interface of Stability Vault
interface IStabilityVault is IERC20, IERC20Metadata {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error WaitAFewBlocks();
    error ExceedSlippage(uint mintToUser, uint minToMint);
    error ExceedMaxSupply(uint maxSupply);
    error NotSupported();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                           EVENTS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event DepositAssets(address indexed account, address[] assets, uint[] amounts, uint mintAmount);
    event WithdrawAssets(
        address indexed sender, address indexed owner, address[] assets, uint sharesAmount, uint[] amountsOut
    );
    event MaxSupply(uint maxShares);
    event VaultName(string newName);
    event VaultSymbol(string newSymbol);
    event LastBlockDefenseDisabled(bool isDisabled);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Underlying assets
    function assets() external view returns (address[] memory);

    /// @notice Immutable vault type ID
    function vaultType() external view returns (string memory);

    /// @dev Calculation of consumed amounts, shares amount and liquidity/underlying value for provided available amounts of strategy assets
    /// @param assets_ Assets suitable for vault strategy. Can be strategy assets, underlying asset or specific set of assets depending on strategy logic.
    /// @param amountsMax Available amounts of assets_ that user wants to invest in vault
    /// @return amountsConsumed Amounts of strategy assets that can be deposited by providing amountsMax
    /// @return sharesOut Amount of vault shares that will be minted
    /// @return valueOut Liquidity value or underlying token amount that will be received by the strategy
    function previewDepositAssets(
        address[] memory assets_,
        uint[] memory amountsMax
    ) external view returns (uint[] memory amountsConsumed, uint sharesOut, uint valueOut);

    /// @dev USD price of share with 18 decimals.
    ///      Not trusted vault share price can be manipulated, used only OFF-CHAIN.
    /// @return price_ Price of 1e18 shares with 18 decimals precision
    /// @return trusted True means oracle price, false means AMM spot price
    function price() external view returns (uint price_, bool trusted);

    /// @dev USD price of assets managed by strategy with 18 decimals
    ///      Not trusted vault share price can be manipulated, used only OFF-CHAIN.
    /// @return tvl_ Total USD value of final assets in vault
    /// @return trusted True means TVL calculated based only on oracle prices, false means AMM spot price was used.
    function tvl() external view returns (uint tvl_, bool trusted);

    /// @dev Minimum 6 blocks between deposit and withdraw check disabled
    function lastBlockDefenseDisabled() external view returns (bool);

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      WRITE FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Deposit final assets (pool assets) to the strategy and minting of vault shares.
    ///      If the strategy interacts with a pool or farms through an underlying token, then it will be minted.
    ///      Emits a {DepositAssets} event with consumed amounts.
    /// @param assets_ Assets suitable for the strategy. Can be strategy assets, underlying asset or specific set of assets depending on strategy logic.
    /// @param amountsMax Available amounts of assets_ that user wants to invest in vault
    /// @param minSharesOut Slippage tolerance. Minimal shares amount which must be received by user.
    /// @param receiver Receiver of deposit. If receiver is zero address, receiver is msg.sender.
    function depositAssets(
        address[] memory assets_,
        uint[] memory amountsMax,
        uint minSharesOut,
        address receiver
    ) external;

    /// @dev Burning shares of vault and obtaining strategy assets.
    /// @param assets_ Assets suitable for the strategy. Can be strategy assets, underlying asset or specific set of assets depending on strategy logic.
    /// @param amountShares Shares amount for burning
    /// @param minAssetAmountsOut Slippage tolerance. Minimal amounts of strategy assets that user must receive.
    /// @return Amount of assets for withdraw. It's related to assets_ one-by-one.
    function withdrawAssets(
        address[] memory assets_,
        uint amountShares,
        uint[] memory minAssetAmountsOut
    ) external returns (uint[] memory);

    /// @dev Burning shares of vault and obtaining strategy assets.
    /// @param assets_ Assets suitable for the strategy. Can be strategy assets, underlying asset or specific set of assets depending on strategy logic.
    /// @param amountShares Shares amount for burning
    /// @param minAssetAmountsOut Slippage tolerance. Minimal amounts of strategy assets that user must receive.
    /// @param receiver Receiver of assets
    /// @param owner Owner of vault shares
    /// @return Amount of assets for withdraw. It's related to assets_ one-by-one.
    function withdrawAssets(
        address[] memory assets_,
        uint amountShares,
        uint[] memory minAssetAmountsOut,
        address receiver,
        address owner
    ) external returns (uint[] memory);

    /// @dev Changing ERC20 name of vault
    function setName(string calldata newName) external;

    /// @dev Changing ERC20 symbol of vault
    function setSymbol(string calldata newSymbol) external;

    /// @dev Enable or disable last block check
    function setLastBlockDefenseDisabled(bool isDisabled) external;
}
