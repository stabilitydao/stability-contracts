// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";

interface IStrategyLogic is IERC721Metadata {
    struct StrategyData {
        uint strategyTokenId;
        string strategyId;
        bytes32 strategyExtra;
    }

    function mint(address to, string memory strategyLogicId) external returns (uint tokenId);
    function setRevenueReceiver(uint tokenId, address receiver) external;
    function tokenStrategyLogic(uint tokenId) external view returns (string memory strategyLogicId);
    function getRevenueReceiver(uint tokenId) external view returns (address receiver);
}
