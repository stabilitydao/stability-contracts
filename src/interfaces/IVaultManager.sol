// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

/// @notice The vaults are assembled at the factory by users through UI.
///         Deployment rights of a vault are tokenized in VaultManager NFT.
///         The holders of these tokens receive a share of the vault revenue and can manage vault if possible.
/// @dev Rewards transfers to token owner or revenue receiver address managed by token owner.
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
interface IVaultManager is IERC721Metadata {
    //region ----- Events -----
    event ChangeVaultParams(uint tokenId, address[] addresses, uint[] nums);
    event SetRevenueReceiver(uint tokenId, address receiver);
    //endregion -- Events -----

    struct VaultData {
        // vault
        uint tokenId;
        address vault;
        string vaultType;
        string name;
        string symbol;
        string[] assetsSymbols;
        string[] rewardAssetsSymbols;
        uint sharePrice;
        uint tvl;
        uint totalApr;
        bytes32 vaultExtra;
        // strategy
        uint strategyTokenId;
        string strategyId;
        string strategySpecific;
        uint strategyApr;
        bytes32 strategyExtra;
    }

    //region ----- View functions -----

    /// @notice Vault address managed by token
    /// @param tokenId ID of NFT. Starts from 0 and increments on mints.
    /// @return vault Address of vault proxy
    function tokenVault(uint tokenId) external view returns (address vault);

    /// @notice Receiver of token owner's platform revenue share
    /// @param tokenId ID of NFT
    /// @return receiver Address of vault manager fees receiver
    function getRevenueReceiver(uint tokenId) external view returns (address receiver);

    /// @notice All vaults data.
    /// The output values are matched by index in the arrays.
    /// @param vaultAddress Vault addresses
    /// @param name Vault name
    /// @param symbol Vault symbol
    /// @param vaultType Vault type ID string
    /// @param strategyId Strategy logic ID string
    /// @param sharePrice Current vault share price in USD. 18 decimals
    /// @param tvl Current vault TVL in USD. 18 decimals
    /// @param totalApr Last total vault APR. Denominator is 100_00.
    /// @param strategyApr Last strategy APR. Denominator is 100_00.
    /// @param strategySpecific Strategy specific name
    function vaults()
        external
        view
        returns (
            address[] memory vaultAddress,
            string[] memory name,
            string[] memory symbol,
            string[] memory vaultType,
            string[] memory strategyId,
            uint[] memory sharePrice,
            uint[] memory tvl,
            uint[] memory totalApr,
            uint[] memory strategyApr,
            string[] memory strategySpecific
        );

    /// @notice All deployed vault addresses
    /// @return vaultAddress Addresses of vault proxy
    function vaultAddresses() external view returns (address[] memory vaultAddress);

    /// @notice Vault extended info getter
    /// @param vault Address of vault proxy
    /// @return strategy
    /// @return strategyAssets
    /// @return underlying
    /// @return assetsWithApr Assets with underlying APRs that can be provided by AprOracle
    /// @return assetsAprs APRs of assets with APR. Matched by index wuth previous param.
    /// @return lastHardWork Last HardWork time
    function vaultInfo(address vault)
        external
        view
        returns (
            address strategy,
            address[] memory strategyAssets,
            address underlying,
            address[] memory assetsWithApr,
            uint[] memory assetsAprs,
            uint lastHardWork
        );

    //endregion -- View functions -----

    //region ----- Write functions -----

    /// @notice Changing managed vault init parameters by Vault Manager (owner of VaultManager NFT)
    /// @param tokenId ID of VaultManager NFT
    /// @param addresses Vault init addresses. Must contain also not changeable init addresses
    /// @param nums Vault init numbers. Must contant also not changeable init numbers
    function changeVaultParams(uint tokenId, address[] memory addresses, uint[] memory nums) external;

    /// @notice Minting of new token on deploying vault by Factory
    /// Only Factory can call this.
    /// @param to User which creates vault
    /// @param vault Address of vault proxy
    /// @return tokenId Minted token ID
    function mint(address to, address vault) external returns (uint tokenId);

    /// @notice Owner of token can change revenue reciever of platform fee share
    /// @param tokenId Owned token ID
    /// @param receiver New revenue receiver address
    function setRevenueReceiver(uint tokenId, address receiver) external;

    //endregion -- Write functions -----
}
