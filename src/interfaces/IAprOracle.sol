// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @dev This oracle is needed to obtain APR of underlying assets in an on-chain environment.
///      These APRs are usually accessible from the protocol APIs.
//       Such data is needed on-chain for the operation of automatic vaults,
///      which can themselves select assets to work with, and to show the overall APR of the strategy in VaultManager NFT.
/// @author Alien Deployer (https://github.com/a17)
interface IAprOracle {

    function getAprs(address[] memory assets) external view returns (uint[] memory aprs);

    function setAprs(address[] memory assets, uint[] memory aprs) external;
}
