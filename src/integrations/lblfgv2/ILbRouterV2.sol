// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ILbRouterV2 {
    function addLiquidity(
        ILbRouterV2.LiquidityParameters memory liquidityParameters
    )
    external
    returns (
        uint256 amountXAdded,
        uint256 amountYAdded,
        uint256 amountXLeft,
        uint256 amountYLeft,
        uint256[] memory depositIds,
        uint256[] memory liquidityMinted
    );

    function addLiquidityNATIVE(
        ILbRouterV2.LiquidityParameters memory liquidityParameters
    )
    external
    payable
    returns (
        uint256 amountXAdded,
        uint256 amountYAdded,
        uint256 amountXLeft,
        uint256 amountYLeft,
        uint256[] memory depositIds,
        uint256[] memory liquidityMinted
    );

    function createLBPair(
        address tokenX,
        address tokenY,
        uint24 activeId,
        uint16 binStep
    ) external returns (address pair);

    function getFactory() external view returns (address lbFactory);

    function getFactoryV2_1() external view returns (address lbFactory);

    function getIdFromPrice(address pair, uint256 price)
    external
    view
    returns (uint24);

    function getLegacyFactory() external view returns (address legacyLBfactory);

    function getLegacyRouter() external view returns (address legacyRouter);

    function getPriceFromId(address pair, uint24 id)
    external
    view
    returns (uint256);

    function getSwapIn(
        address pair,
        uint128 amountOut,
        bool swapForY
    )
    external
    view
    returns (
        uint128 amountIn,
        uint128 amountOutLeft,
        uint128 fee
    );

    function getSwapOut(
        address pair,
        uint128 amountIn,
        bool swapForY
    )
    external
    view
    returns (
        uint128 amountInLeft,
        uint128 amountOut,
        uint128 fee
    );

    function getV1Factory() external view returns (address factoryV1);

    function getWNATIVE() external view returns (address wnative);

    function removeLiquidity(
        address tokenX,
        address tokenY,
        uint16 binStep,
        uint256 amountXMin,
        uint256 amountYMin,
        uint256[] memory ids,
        uint256[] memory amounts,
        address to,
        uint256 deadline
    ) external returns (uint256 amountX, uint256 amountY);

    function removeLiquidityNATIVE(
        address token,
        uint16 binStep,
        uint256 amountTokenMin,
        uint256 amountNATIVEMin,
        uint256[] memory ids,
        uint256[] memory amounts,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountNATIVE);

    function swapExactNATIVEForTokens(
        uint256 amountOutMin,
        ILbRouterV2.Path memory path,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountOut);

    function swapExactNATIVEForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        ILbRouterV2.Path memory path,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountOut);

    function swapExactTokensForNATIVE(
        uint256 amountIn,
        uint256 amountOutMinNATIVE,
        ILbRouterV2.Path memory path,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);

    function swapExactTokensForNATIVESupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMinNATIVE,
        ILbRouterV2.Path memory path,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        ILbRouterV2.Path memory path,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        ILbRouterV2.Path memory path,
        address to,
        uint256 deadline
    ) external returns (uint256 amountOut);

    function swapNATIVEForExactTokens(
        uint256 amountOut,
        ILbRouterV2.Path memory path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amountsIn);

    function swapTokensForExactNATIVE(
        uint256 amountNATIVEOut,
        uint256 amountInMax,
        ILbRouterV2.Path memory path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amountsIn);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        ILbRouterV2.Path memory path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amountsIn);

    function sweep(
        address token,
        address to,
        uint256 amount
    ) external;

    function sweepLBToken(
        address lbToken,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts
    ) external;

    receive() external payable;

    struct LiquidityParameters {
        address tokenX;
        address tokenY;
        uint256 binStep;
        uint256 amountX;
        uint256 amountY;
        uint256 amountXMin;
        uint256 amountYMin;
        uint256 activeIdDesired;
        uint256 idSlippage;
        int256[] deltaIds;
        uint256[] distributionX;
        uint256[] distributionY;
        address to;
        address refundTo;
        uint256 deadline;
    }

    struct Path {
        uint256[] pairBinSteps;
        uint8[] versions;
        address[] tokenPath;
    }
}



