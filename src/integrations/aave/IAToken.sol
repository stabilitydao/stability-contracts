// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IAToken {
  event BalanceTransfer(address indexed from, address indexed to, uint value, uint index);

  function mint(
    address caller,
    address onBehalfOf,
    uint amount,
    uint index
  ) external returns (bool);

  function burn(address from, address receiverOfUnderlying, uint amount, uint index) external;

  function mintToTreasury(uint amount, uint index) external;

  function transferOnLiquidation(address from, address to, uint value) external;

  function transferUnderlyingTo(address target, uint amount) external;

  function handleRepayment(address user, address onBehalfOf, uint amount) external;

  function permit(
    address owner,
    address spender,
    uint value,
    uint deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external;

  function UNDERLYING_ASSET_ADDRESS() external view returns (address);

  function POOL() external view returns (address);

  function RESERVE_TREASURY_ADDRESS() external view returns (address);

  function DOMAIN_SEPARATOR() external view returns (bytes32);

  function nonces(address owner) external view returns (uint);

  function balanceOf(address account) external view returns (uint);

  function scaledBalanceOf(address user) external view returns (uint);

  function rescueTokens(address token, address to, uint amount) external;
}