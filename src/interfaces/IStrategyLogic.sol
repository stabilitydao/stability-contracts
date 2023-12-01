// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

/// @dev Interface of developed strategy logic NFT
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
interface IStrategyLogic is IERC721Metadata {
    //region ----- Events -----
    event SetRevenueReceiver(uint tokenId, address receiver);
    //endregion -- Events -----

    struct StrategyData {
        uint strategyTokenId;
        string strategyId;
        bytes32 strategyExtra;
    }

    /// @notice Minting of new developed strategy by the factory
    /// @dev Parameters from StrategyDeveloperLib, StrategyIdLib.
    /// Only factory can call it.
    /// @param to Strategy developer address
    /// @param strategyLogicId Strategy logic ID string
    /// @return tokenId Minted token ID
    function mint(address to, string memory strategyLogicId) external returns (uint tokenId);

    /// @notice Owner of token can change address for receiving strategy logic revenue share
    /// Only owner of token can call it.
    /// @param tokenId Owned token ID
    /// @param receiver Address for receiving revenue
    function setRevenueReceiver(uint tokenId, address receiver) external;

    /// @notice Token ID to strategy logic ID map
    /// @param tokenId Owned token ID
    /// @return strategyLogicId Strategy logic ID string
    function tokenStrategyLogic(uint tokenId) external view returns (string memory strategyLogicId);

    /// @notice Current revenue reciever for token
    /// @param tokenId Token ID
    /// @return receiver Address for receiving revenue
    function getRevenueReceiver(uint tokenId) external view returns (address receiver);
}
