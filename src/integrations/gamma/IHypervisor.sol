// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IHypervisor is IERC20 {
    function pool() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getBasePosition() external view returns (uint128 liquidity, uint amount0, uint amount1);

    function getLimitPosition() external view returns (uint128 liquidity, uint amount0, uint amount1);

    function getTotalAmounts() external view returns (uint total0, uint total1);

    /// @param shares Number of liquidity tokens to redeem as pool assets
    /// @param to Address to which redeemed pool assets are sent
    /// @param from Address from which liquidity tokens are sent
    /// @param minAmounts min amount0,1 returned for shares of liq
    /// @return amount0 Amount of token0 redeemed by the submitted liquidity tokens
    /// @return amount1 Amount of token1 redeemed by the submitted liquidity tokens
    function withdraw(
        uint shares,
        address to,
        address from,
        uint[4] memory minAmounts
    ) external returns (uint amount0, uint amount1);
}
