// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/// @notice On-chain price quoter and swapper by predefined routes
/// @author Alien Deployer (https://github.com/a17)
interface ISwapper {
  event Swap(address indexed tokenIn, address indexed tokenOut, uint amount);
  event PoolAdded(PoolData poolData);
  event PoolRemoved(address token);
  event BlueChipAdded(PoolData poolData);
  event ThresholdChanged(address token, uint threshold);

  struct PoolData {
    address pool;
    address dexAdapter;
    address tokenIn;
    address tokenOut;
  }

  struct AddPoolData {
    address pool;
    string dexAdapterId;
    address tokenIn;
    address tokenOut;
  }

  function assets() external view returns(address[] memory);

  function bcAssets() external view returns(address[] memory);

  function allAssets() external view returns(address[] memory);

  function addPools(PoolData[] memory pools, bool rewrite) external;

  function addPools(AddPoolData[] memory pools, bool rewrite) external;

  /// @dev Add largest pools with the most popular tokens on the current network
  /// @param pools_ PoolData array with pool, tokens and DeX adapter address
  /// @param rewrite Change exist pool records
  function addBlueChipsPools(PoolData[] memory pools_, bool rewrite) external;

  /// @dev Add largest pools with the most popular tokens on the current network
  /// @param pools_ AddPoolData array with pool, tokens and DeX adapter string ID
  /// @param rewrite Change exist pool records
  function addBlueChipsPools(AddPoolData[] memory pools_, bool rewrite) external;

  function setThreshold(address token, uint threshold_) external;

  function threshold(address token) external view returns (uint threshold);

  function getPrice(address tokenIn, address tokenOut, uint amount) external view returns (uint);

  function getPriceForRoute(PoolData[] memory route, uint amount) external view returns (uint);

  function isRouteExist(address tokenIn, address tokenOut) external view returns (bool);

  function buildRoute(
    address tokenIn,
    address tokenOut
  ) external view returns (PoolData[] memory route, string memory errorMessage);

  function swap(
    address tokenIn,
    address tokenOut,
    uint amount,
    uint priceImpactTolerance
  ) external;

  function swapWithRoute(
    PoolData[] memory route,
    uint amount,
    uint priceImpactTolerance
  ) external;
}
