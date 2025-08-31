// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.24;

/// @notice Restored from 0xbA1333333333a1BA1108E8412f11850A5C319bA9 (sonic)
interface IVaultMainV3 {
  struct TokenConfig {
    address token;
    uint8 tokenType;
    address rateProvider;
    bool paysYieldFees;
  }

  struct PoolRoleAccounts {
    address pauseManager;
    address swapFeeManager;
    address poolCreator;
  }

  struct HooksConfig {
    bool enableHookAdjustedAmounts;
    bool shouldCallBeforeInitialize;
    bool shouldCallAfterInitialize;
    bool shouldCallComputeDynamicSwapFee;
    bool shouldCallBeforeSwap;
    bool shouldCallAfterSwap;
    bool shouldCallBeforeAddLiquidity;
    bool shouldCallAfterAddLiquidity;
    bool shouldCallBeforeRemoveLiquidity;
    bool shouldCallAfterRemoveLiquidity;
    address hooksContract;
  }

  struct LiquidityManagement {
    bool disableUnbalancedLiquidity;
    bool enableAddLiquidityCustom;
    bool enableRemoveLiquidityCustom;
    bool enableDonation;
  }

  struct AddLiquidityParams {
    address pool;
    address to;
    uint256[] maxAmountsIn;
    uint256 minBptAmountOut;
    uint8 kind;
    bytes userData;
  }

  struct BufferWrapOrUnwrapParams {
    uint8 kind;
    uint8 direction;
    address wrappedToken;
    uint256 amountGivenRaw;
    uint256 limitRaw;
  }

  struct RemoveLiquidityParams {
    address pool;
    address from;
    uint256 maxBptAmountIn;
    uint256[] minAmountsOut;
    uint8 kind;
    bytes userData;
  }

  struct VaultSwapParams {
    uint8 kind;
    address pool;
    address tokenIn;
    address tokenOut;
    uint256 amountGivenRaw;
    uint256 limitRaw;
    bytes userData;
  }

  fallback() external payable;

  function addLiquidity(AddLiquidityParams memory params)
  external
  returns (
    uint256[] memory amountsIn,
    uint256 bptAmountOut,
    bytes memory returnData
  );

  function erc4626BufferWrapOrUnwrap(BufferWrapOrUnwrapParams memory params)
  external
  returns (
    uint256 amountCalculatedRaw,
    uint256 amountInRaw,
    uint256 amountOutRaw
  );

  function getPoolTokenCountAndIndexOfToken(address pool, address token)
  external
  view
  returns (uint256, uint256);

  function getVaultExtension() external view returns (address);

  function reentrancyGuardEntered() external view returns (bool);

  function removeLiquidity(RemoveLiquidityParams memory params)
  external
  returns (
    uint256 bptAmountIn,
    uint256[] memory amountsOut,
    bytes memory returnData
  );

  function sendTo(address token, address to, uint256 amount) external;

  function settle(address token, uint256 amountHint) external returns (uint256 credit);

  function swap(VaultSwapParams memory vaultSwapParams)
  external
  returns (
    uint256 amountCalculated,
    uint256 amountIn,
    uint256 amountOut
  );

  function transfer(address owner, address to, uint256 amount) external returns (bool);

  function transferFrom(address spender, address from, address to, uint256 amount) external returns (bool);

  /// @notice Creates a context for a sequence of operations (i.e., "unlocks" the Vault).
  /// @dev Performs a callback on msg.sender with arguments provided in `data`. The Callback is `transient`,
  /// meaning all balances for the caller have to be settled at the end.
  /// Implementation in balancer-v3-monorepo is following:
  ///     function unlock(bytes calldata data) external transient returns (bytes memory result) {
  ///        return (msg.sender).functionCall(data);
  ///    }
  /// @param data Contains function signature and args to be passed to the msg.sender
  /// @return result Resulting data from the call
  function unlock(bytes memory data) external returns (bytes memory result);

  receive() external payable;
}

