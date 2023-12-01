// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @title Synthetic bridged token factory
/// @author Alien Deployer (https://github.com/a17)
interface IChildTokenFactory {
    /// @notice Deploy new child (synthetic) ERC-20 token
    /// @param parentToken Parent natural ERC-20 token in other blockchain
    /// @param parentChainId Parent chain ID
    /// @param name Name of new child token
    /// @param symbol Symbol of new child token
    /// @return Address of deployed child ERC-20 token
    function deployChildERC20(
        address parentToken,
        uint64 parentChainId,
        string memory name,
        string memory symbol
    ) external returns (address);

    /// @notice Deploy new child (synthetic) ERC-721 token
    /// @param parentToken Parent natural ERC-721 token in other blockchain
    /// @param parentChainId Parent chain ID
    /// @param name Name of new child token
    /// @param symbol Symbol of new child token
    /// @param baseURI Base URI for computing {tokenURI}
    /// @return Address of deployed child ERC-721 token
    function deployChildERC721(
        address parentToken,
        uint64 parentChainId,
        string memory name,
        string memory symbol,
        string memory baseURI
    ) external returns (address);
}
