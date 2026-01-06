// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ILbQuoterV2 {
    struct Quote {
        address[] route;
        address[] pairs;
        uint256[] binSteps;
        uint8[] versions;
        uint128[] amounts;
        uint128[] virtualAmountsWithoutSlippage;
        uint128[] fees;
    }

    function findBestPathFromAmountIn(address[] memory route, uint128 amountIn) external view
    returns (Quote memory quote);

    function findBestPathFromAmountOut(
        address[] memory route,
        uint128 amountOut
    ) external view returns (Quote memory quote);

    function getFactoryV1() external view returns (address factoryV1);

    function getFactoryV2_1() external view returns (address factoryV2_1);

    function getFactoryV2_2() external view returns (address factoryV2_2);

    function getLegacyFactoryV2() external view returns (address legacyFactoryV2);

    function getLegacyRouterV2() external view returns (address legacyRouterV2);

    function getRouterV2_1() external view returns (address routerV2_1);

    function getRouterV2_2() external view returns (address routerV2_2);


}
