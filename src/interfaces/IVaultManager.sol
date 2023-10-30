// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @notice The vaults are assembled at the factory by users through UI.
///         Deployment rights of a vault are tokenized in VaultManager NFT.
///         The holders of these tokens receive a share of the vault revenue and can manage vault if possible.
/// @dev Rewards transfers to token owner or revenue receiver address managed by token owner.
/// @author Alien Deployer (https://github.com/a17)
interface IVaultManager is IERC721 {
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

    function tokenVault(uint tokenId) external view returns (address vault);

    function getRevenueReceiver(uint tokenId) external view returns (address receiver);

    function vaults() external view returns(
        address[] memory vaultAddress,
        string[] memory symbol,
        string[] memory vaultType,
        string[] memory strategyId,
        uint[] memory sharePrice,
        uint[] memory tvl
    );

    function vaultAddresses() external view returns(address[] memory vaultAddress);

    //endregion -- View functions -----

    //region ----- Write functions -----

    function changeVaultParams(uint tokenId, address[] memory addresses, uint[] memory nums) external;

    function mint(address to, address vault) external returns (uint tokenId);

    function setRevenueReceiver(uint tokenId, address receiver) external;

    //endregion -- Write functions -----
}
