// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @dev This oracle is needed to obtain APR of underlying assets in an on-chain environment.
///      These APRs are usually accessible from the protocol APIs.
//       Such data is needed on-chain for the operation of automatic vaults,
///      which can themselves select assets to work with, and to show the overall APR of the strategy in VaultManager NFT.
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
interface IAprOracle {
    //region ----- Events -----
    event SetAprs(address[] assets, uint[] aprs);
    //endregion -- Events -----

    /// @notice Get stored APR of assets with APR
    /// @param assets Underlying assets. Can be liquidity managing vault (Gamma's HyperVisor etc), LST (stETH etc) or other
    /// @return aprs APRs stored in oracle with 18 decimals precision
    function getAprs(address[] memory assets) external view returns (uint[] memory aprs);

    /// @notice Set APRs for asset with APR
    /// @param assets Underlying assets. Can be liquidity managing vault (Gamma's HyperVisor etc), LST (stETH etc) or other
    /// @param aprs Underlying APRs with 18 decimals precision
    function setAprs(address[] memory assets, uint[] memory aprs) external;
}
