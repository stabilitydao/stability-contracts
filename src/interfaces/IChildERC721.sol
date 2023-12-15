// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IChildERC721 {
    function bridge() external view returns (address);

    function parent() external view returns (address token, uint64 chainId);

    function mint(address to, uint tokenId) external;

    function burn(address from, uint tokenId) external;
}
