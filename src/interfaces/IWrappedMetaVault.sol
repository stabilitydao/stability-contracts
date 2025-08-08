// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IWrappedMetaVault is IERC4626 {
    event WithdrawUnderlying(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        address underlying,
        uint underlyingOut,
        uint assetsAmountIn,
        address recoveryToken,
        uint recoveryAmount
    );

    error Slippage(uint value, uint threshold);

    /// @custom:storage-location erc7201:stability.WrappedMetaVault
    struct WrappedMetaVaultStorage {
        address metaVault;
        bool isMulti;
    }

    /// @dev Init
    function initialize(address platform_, address metaVault) external;

    /// @notice Address of MetaVault wrapped by this contract
    function metaVault() external view returns (address);

    /// @notice Deposits {assets} of the underlying token into the Vault and grants {shares} to the {receiver}
    /// @param assets The amount of underlying tokens to deposit
    /// @param receiver The address to receive the Vault shares
    /// @param minShares The minimum number of shares to be minted (slippage protection)
    /// @return shares The number of shares minted
    function deposit(uint assets, address receiver, uint minShares) external returns (uint);

    /// @notice Mints {shares} of the Vault to {receiver} by transferring the necessary amount of underlying tokens from the sender
    /// @param shares The amount of Vault shares to mint
    /// @param receiver The address to receive the Vault shares
    /// @param maxAssets The maximum amount of underlying tokens that can be spent (slippage protection)
    /// @return assets The amount of underlying tokens used to mint shares
    function mint(uint shares, address receiver, uint maxAssets) external returns (uint);

    /// @notice Withdraws {assets} of the underlying token from the Vault by redeeming shares from {owner}
    /// @param assets The amount of underlying tokens to withdraw
    /// @param receiver The address to receive the underlying tokens
    /// @param owner The address from which to burn Vault shares
    /// @param maxShares The maximum number of shares to be burned (slippage protection)
    /// @return shares The amount of Vault shares burned
    function withdraw(uint assets, address receiver, address owner, uint maxShares) external returns (uint);

    /// @notice Redeems {shares} of the Vault from {owner} and transfers the corresponding amount of underlying tokens to {receiver}
    /// @param shares The amount of Vault shares to redeem
    /// @param receiver The address to receive the underlying tokens
    /// @param owner The address from which to burn Vault shares
    /// @param minAssets The minimum amount of underlying tokens to be received (slippage protection)
    /// @return assets The amount of underlying tokens withdrawn
    function redeem(uint shares, address receiver, address owner, uint minAssets) external returns (uint);
}
