// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IDefiEdgeStrategy {
    struct Tick {
        int24 tickLower;
        int24 tickUpper;
    }

    function pool() external view returns (address);

    function ticks(uint i) external view returns (Tick memory);

    function getTicks() external view returns (Tick[] memory);

    function usdAsBase(uint i) external view returns (bool);

    function factory() external view returns (address);

    function totalSupply() external view returns (uint);

    function reserve0() external view returns (uint);

    function reserve1() external view returns (uint);

    /**
     * @notice Get's assets under management with realtime fees
     * @param _includeFee Whether to include pool fees in AUM or not. (passing true will also collect fees from pool)
     * @param amount0 Total AUM of token0 including the fees  ( if _includeFee is passed true)
     * @param amount1 Total AUM of token1 including the fees  ( if _includeFee is passed true)
     * @param totalFee0 Total fee of token0 including the fees  ( if _includeFee is passed true)
     * @param totalFee1 Total fee of token1 including the fees  ( if _includeFee is passed true)
     */
    function getAUMWithFees(bool _includeFee)
        external
        returns (uint amount0, uint amount1, uint totalFee0, uint totalFee1);

    /**
     * @notice Adds liquidity to the primary range
     * @param _amount0 Amount of token0
     * @param _amount1 Amount of token1
     * @param _amount0Min Minimum amount of token0 to be minted
     * @param _amount1Min Minimum amount of token1 to be minted
     * @param _minShare Minimum amount of shares to be received to the user
     * @return amount0 Amount of token0 deployed
     * @return amount1 Amount of token1 deployed
     * @return share Number of shares minted
     */
    function mint(
        uint _amount0,
        uint _amount1,
        uint _amount0Min,
        uint _amount1Min,
        uint _minShare
    ) external returns (uint amount0, uint amount1, uint share);

    /**
     * @notice Burn liquidity and transfer tokens back to the user
     * @param _shares Shares to be burned
     * @param _amount0Min Mimimum amount of token0 to be received
     * @param _amount1Min Minimum amount of token1 to be received
     * @return collect0 The amount of token0 returned to the user
     * @return collect1 The amount of token1 returned to the user
     */
    function burn(uint _shares, uint _amount0Min, uint _amount1Min) external returns (uint collect0, uint collect1);
}
