// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAmmAdapter} from "./IAmmAdapter.sol";

/// @dev Get price, swap, liquidity calculations. Used by strategies and swapper
/// @author dvpublic (https://github.com/dvpublic)
interface IMetaVaultAmmAdapter is IAmmAdapter {
    /// @notice Asset in MetaVault.vaultForDeposit
    function assetForDeposit(address pool) external view returns (address);

    /// @notice Asset in MetaVault.vaultForWithdraw
    function assetForWithdraw(address pool) external view returns (address);
}
