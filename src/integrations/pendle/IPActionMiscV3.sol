// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./IPAllActionTypeV3.sol";

/// @notice Restored from 0x373Dba2055Ad40cb4815148bC47cd1DC16e92E44
interface IPActionMiscV3 {
  error SimulationResults(bool success, bytes res);
  event AddLiquidityDualSyAndPt(
    address indexed caller,
    address indexed market,
    address indexed receiver,
    uint256 netSyUsed,
    uint256 netPtUsed,
    uint256 netLpOut
  );
  event AddLiquidityDualTokenAndPt(
    address indexed caller,
    address indexed market,
    address indexed tokenIn,
    address receiver,
    uint256 netTokenUsed,
    uint256 netPtUsed,
    uint256 netLpOut,
    uint256 netSyInterm
  );
  event AddLiquiditySinglePt(
    address indexed caller,
    address indexed market,
    address indexed receiver,
    uint256 netPtIn,
    uint256 netLpOut
  );
  event AddLiquiditySingleSy(
    address indexed caller,
    address indexed market,
    address indexed receiver,
    uint256 netSyIn,
    uint256 netLpOut
  );
  event AddLiquiditySingleSyKeepYt(
    address indexed caller,
    address indexed market,
    address indexed receiver,
    uint256 netSyIn,
    uint256 netSyMintPy,
    uint256 netLpOut,
    uint256 netYtOut
  );
  event AddLiquiditySingleToken(
    address indexed caller,
    address indexed market,
    address indexed token,
    address receiver,
    uint256 netTokenIn,
    uint256 netLpOut,
    uint256 netSyInterm
  );
  event AddLiquiditySingleTokenKeepYt(
    address indexed caller,
    address indexed market,
    address indexed token,
    address receiver,
    uint256 netTokenIn,
    uint256 netLpOut,
    uint256 netYtOut,
    uint256 netSyMintPy,
    uint256 netSyInterm
  );
  event ExitPostExpToSy(
    address indexed caller,
    address indexed market,
    address indexed receiver,
    uint256 netLpIn,
    ExitPostExpReturnParams params
  );
  event ExitPostExpToToken(
    address indexed caller,
    address indexed market,
    address indexed token,
    address receiver,
    uint256 netLpIn,
    uint256 totalTokenOut,
    ExitPostExpReturnParams params
  );
  event ExitPreExpToSy(
    address indexed caller,
    address indexed market,
    address indexed receiver,
    uint256 netLpIn,
    ExitPreExpReturnParams params
  );
  event ExitPreExpToToken(
    address indexed caller,
    address indexed market,
    address indexed token,
    address receiver,
    uint256 netLpIn,
    uint256 totalTokenOut,
    ExitPreExpReturnParams params
  );
  event MintPyFromSy(
    address indexed caller,
    address indexed receiver,
    address indexed YT,
    uint256 netSyIn,
    uint256 netPyOut
  );
  event MintPyFromToken(
    address indexed caller,
    address indexed tokenIn,
    address indexed YT,
    address receiver,
    uint256 netTokenIn,
    uint256 netPyOut,
    uint256 netSyInterm
  );
  event MintSyFromToken(
    address indexed caller,
    address indexed tokenIn,
    address indexed SY,
    address receiver,
    uint256 netTokenIn,
    uint256 netSyOut
  );
  event OwnershipTransferred(
    address indexed previousOwner,
    address indexed newOwner
  );
  event RedeemPyToSy(
    address indexed caller,
    address indexed receiver,
    address indexed YT,
    uint256 netPyIn,
    uint256 netSyOut
  );
  event RedeemPyToToken(
    address indexed caller,
    address indexed tokenOut,
    address indexed YT,
    address receiver,
    uint256 netPyIn,
    uint256 netTokenOut,
    uint256 netSyInterm
  );
  event RedeemSyToToken(
    address indexed caller,
    address indexed tokenOut,
    address indexed SY,
    address receiver,
    uint256 netSyIn,
    uint256 netTokenOut
  );
  event RemoveLiquidityDualSyAndPt(
    address indexed caller,
    address indexed market,
    address indexed receiver,
    uint256 netLpToRemove,
    uint256 netPtOut,
    uint256 netSyOut
  );
  event RemoveLiquidityDualTokenAndPt(
    address indexed caller,
    address indexed market,
    address indexed tokenOut,
    address receiver,
    uint256 netLpToRemove,
    uint256 netPtOut,
    uint256 netTokenOut,
    uint256 netSyInterm
  );
  event RemoveLiquiditySinglePt(
    address indexed caller,
    address indexed market,
    address indexed receiver,
    uint256 netLpToRemove,
    uint256 netPtOut
  );
  event RemoveLiquiditySingleSy(
    address indexed caller,
    address indexed market,
    address indexed receiver,
    uint256 netLpToRemove,
    uint256 netSyOut
  );
  event RemoveLiquiditySingleToken(
    address indexed caller,
    address indexed market,
    address indexed token,
    address receiver,
    uint256 netLpToRemove,
    uint256 netTokenOut,
    uint256 netSyInterm
  );
  event SelectorToFacetSet(bytes4 indexed selector, address indexed facet);
  event SwapPtAndSy(
    address indexed caller,
    address indexed market,
    address indexed receiver,
    int256 netPtToAccount,
    int256 netSyToAccount
  );
  event SwapPtAndToken(
    address indexed caller,
    address indexed market,
    address indexed token,
    address receiver,
    int256 netPtToAccount,
    int256 netTokenToAccount,
    uint256 netSyInterm
  );
  event SwapYtAndSy(
    address indexed caller,
    address indexed market,
    address indexed receiver,
    int256 netYtToAccount,
    int256 netSyToAccount
  );
  event SwapYtAndToken(
    address indexed caller,
    address indexed market,
    address indexed token,
    address receiver,
    int256 netYtToAccount,
    int256 netTokenToAccount,
    uint256 netSyInterm
  );

  function boostMarkets(address[] memory markets) external;

  function callAndReflect(
    address reflector,
    bytes memory selfCall1,
    bytes memory selfCall2,
    bytes memory reflectCall
  )
  external
  payable
  returns (
    bytes memory selfRes1,
    bytes memory selfRes2,
    bytes memory reflectRes
  );

  function exitPostExpToSy(
    address receiver,
    address market,
    uint256 netPtIn,
    uint256 netLpIn,
    uint256 minSyOut
  ) external returns (ExitPostExpReturnParams memory params);

  function exitPostExpToToken(
    address receiver,
    address market,
    uint256 netPtIn,
    uint256 netLpIn,
    TokenOutput memory output
  )
  external
  returns (uint256 totalTokenOut, ExitPostExpReturnParams memory params);

  function exitPreExpToSy(
    address receiver,
    address market,
    uint256 netPtIn,
    uint256 netYtIn,
    uint256 netLpIn,
    uint256 minSyOut,
    LimitOrderData memory limit
  ) external returns (ExitPreExpReturnParams memory params);

  function exitPreExpToToken(
    address receiver,
    address market,
    uint256 netPtIn,
    uint256 netYtIn,
    uint256 netLpIn,
    TokenOutput memory output,
    LimitOrderData memory limit
  )
  external
  returns (uint256 totalTokenOut, ExitPreExpReturnParams memory params);

  function mintPyFromSy(
    address receiver,
    address YT,
    uint256 netSyIn,
    uint256 minPyOut
  ) external returns (uint256 netPyOut);

  function mintPyFromToken(
    address receiver,
    address YT,
    uint256 minPyOut,
    TokenInput memory input
  ) external payable returns (uint256 netPyOut, uint256 netSyInterm);

  function mintSyFromToken(
    address receiver,
    address SY,
    uint256 minSyOut,
    TokenInput memory input
  ) external payable returns (uint256 netSyOut);

  function multicall(IPActionMiscV3.Call3[] memory calls)
  external
  payable
  returns (IPActionMiscV3.Result[] memory res);

  function redeemDueInterestAndRewards(
    address user,
    address[] memory sys,
    address[] memory yts,
    address[] memory markets
  ) external;

  function redeemDueInterestAndRewardsV2(
    address[] memory SYs,
    RedeemYtIncomeToTokenStruct[] memory YTs,
    address[] memory markets,
    address pendleSwap,
    SwapDataExtra[] memory swaps
  )
  external
  returns (
    uint256[] memory netOutFromSwaps,
    uint256[] memory netInterests
  );

  function redeemPyToSy(
    address receiver,
    address YT,
    uint256 netPyIn,
    uint256 minSyOut
  ) external returns (uint256 netSyOut);

  function redeemPyToToken(
    address receiver,
    address YT,
    uint256 netPyIn,
    TokenOutput memory output
  ) external returns (uint256 netTokenOut, uint256 netSyInterm);

  function redeemSyToToken(
    address receiver,
    address SY,
    uint256 netSyIn,
    TokenOutput memory output
  ) external returns (uint256 netTokenOut);

  function simulate(address target, bytes memory data) external payable;

  function swapTokenToTokenViaSy(
    address receiver,
    address SY,
    TokenInput memory input,
    address tokenRedeemSy,
    uint256 minTokenOut
  ) external payable returns (uint256 netTokenOut, uint256 netSyInterm);

  function swapTokensToTokens(
    address pendleSwap,
    SwapDataExtra[] memory swaps,
    uint256[] memory netSwaps
  ) external payable returns (uint256[] memory netOutFromSwaps);

  struct Call3 {
    bool allowFailure;
    bytes callData;
  }

  struct Result {
    bool success;
    bytes returnData;
  }
}
