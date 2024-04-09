// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../interfaces/IAmmAdapter.sol";

contract MockAmmAdapter is IAmmAdapter {
    string internal constant _DEX_ADAPTER_ID = "MOCKSWAP";
    string internal constant _DEX_ADAPTER_VERSION = "1.0.0";

    address internal _asset0;
    address internal _asset1;

    // add this to be excluded from coverage report
    function test() public {}

    constructor(address asset0, address asset1) {
        _asset0 = asset0;
        _asset1 = asset1;
    }

    function init(address) external {}

    function poolTokens(address /*pool*/ ) external view returns (address[] memory) {
        address[] memory assets = new address[](2);
        assets[0] = _asset0;
        assets[1] = _asset1;
        return assets;
    }

    function getLiquidityForAmounts(
        address, /* pool*/
        uint[] memory amounts
    ) public pure returns (uint liquidity, uint[] memory amountsConsumed) {
        uint price0to1 = 2e6;

        amountsConsumed = new uint[](2);
        if (amounts[0] * price0to1 / 1e18 < amounts[1]) {
            amountsConsumed[0] = amounts[0];
            amountsConsumed[1] = amounts[0] * price0to1 / 1e18;
        } else {
            amountsConsumed[0] = amounts[1] * 1e18 / price0to1;
            amountsConsumed[1] = amounts[1];
        }

        liquidity = amountsConsumed[0] * amountsConsumed[1];
    }

    function getLiquidityForAmounts(
        address pool,
        uint[] memory amounts,
        int24[] memory /* ticks*/
    ) external pure returns (uint liquidity, uint[] memory amountsConsumed) {
        return getLiquidityForAmounts(pool, amounts);
    }

    function getAmountsForLiquidity(
        address, /*pool*/
        int24[] memory, /*ticks*/
        uint128 /*liquidity*/
    ) external pure returns (uint[] memory /*amounts*/ ) {
        revert("unavailable");
    }

    function getAmountsForLiquidity(
        address, /*pool*/
        int24, /*lowerTick*/
        int24, /*upperTick*/
        uint128 /*liquidity*/
    ) public pure returns (uint, /*amount0*/ uint /*amount1*/ ) {
        revert("unavailable");
    }

    /// @inheritdoc IAmmAdapter
    function getProportions(address) external pure returns (uint[] memory) {
        uint[] memory p = new uint[](2);
        p[0] = 5e17;
        p[1] = 1e18 - p[0];
        return p;
    }

    function swap(
        address pool,
        address tokenIn,
        address tokenOut,
        address recipient,
        uint priceImpactTolerance
    ) external {}

    function getPrice(
        address, /*pool*/
        address, /*tokenIn*/
        address, /*tokenOut*/
        uint /*amount*/
    ) external pure returns (uint) {
        return 2e18;
    }

    /// @inheritdoc IAmmAdapter
    function ammAdapterId() external pure returns (string memory) {
        return _DEX_ADAPTER_ID;
    }

    function DEX_ADAPTER_VERSION() external pure returns (string memory) {
        return _DEX_ADAPTER_VERSION;
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IAmmAdapter).interfaceId;
    }
}
