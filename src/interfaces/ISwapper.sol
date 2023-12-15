// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @notice On-chain price quoter and swapper by predefined routes
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
/// @author 0xhokugava (https://github.com/0xhokugava)
interface ISwapper {
    event Swap(address indexed tokenIn, address indexed tokenOut, uint amount);
    event PoolAdded(PoolData poolData, bool assetAdded);
    event PoolRemoved(address token);
    event BlueChipAdded(PoolData poolData);
    event ThresholdChanged(address[] tokenIn, uint[] thresholdAmount);
    event BlueChipPoolRemoved(address tokenIn, address tokenOut);

    //region ----- Custom Errors -----
    error UnknownAMMAdapter();
    error LessThenThreshold(uint minimumAmount);
    error NoRouteFound();
    error NoRoutesForAssets();
    //endregion -- Custom Errors -----

    struct PoolData {
        address pool;
        address ammAdapter;
        address tokenIn;
        address tokenOut;
    }

    struct AddPoolData {
        address pool;
        string ammAdapterId;
        address tokenIn;
        address tokenOut;
    }

    /// @notice All assets in pools added to Swapper
    /// @return Addresses of assets
    function assets() external view returns (address[] memory);

    /// @notice All blue chip assets in blue chip pools added to Swapper
    /// @return Addresses of blue chip assets
    function bcAssets() external view returns (address[] memory);

    /// @notice All assets in Swapper
    /// @return Addresses of assets and blue chip assets
    function allAssets() external view returns (address[] memory);

    /// @notice Add pools with largest TVL
    /// @param pools Largest pools with AMM adapter addresses
    /// @param rewrite Rewrite pool for tokenIn
    function addPools(PoolData[] memory pools, bool rewrite) external;

    /// @notice Add pools with largest TVL
    /// @param pools Largest pools with AMM adapter ID string
    /// @param rewrite Rewrite pool for tokenIn
    function addPools(AddPoolData[] memory pools, bool rewrite) external;

    /// @notice Add largest pools with the most popular tokens on the current network
    /// @param pools_ PoolData array with pool, tokens and AMM adapter address
    /// @param rewrite Change exist pool records
    function addBlueChipsPools(PoolData[] memory pools_, bool rewrite) external;

    /// @notice Add largest pools with the most popular tokens on the current network
    /// @param pools_ AddPoolData array with pool, tokens and AMM adapter string ID
    /// @param rewrite Change exist pool records
    function addBlueChipsPools(AddPoolData[] memory pools_, bool rewrite) external;

    /// @notice Retrieves pool data for a specified token swap in Blue Chip Pools.
    /// @dev This function provides information about the pool associated with the specified input and output tokens.
    /// @param tokenIn The input token address.
    /// @param tokenOut The output token address.
    /// @return poolData The data structure containing information about the Blue Chip Pool.
    /// @custom:opcodes view
    function blueChipsPools(address tokenIn, address tokenOut) external view returns (PoolData memory poolData);

    /// @notice Set swap threshold for token
    /// @dev Prevents dust swap.
    /// @param tokenIn Swap input token
    /// @param thresholdAmount Minimum amount of token for executing swap
    function setThresholds(address[] memory tokenIn, uint[] memory thresholdAmount) external;

    /// @notice Swap threshold for token
    /// @param token Swap input token
    /// @return threshold_ Minimum amount of token for executing swap
    function threshold(address token) external view returns (uint threshold_);

    /// @notice Price of given tokenIn against tokenOut
    /// @param tokenIn Swap input token
    /// @param tokenOut Swap output token
    /// @param amount Amount of tokenIn. If provide zero then amount is 1.0.
    /// @return Amount of tokenOut with decimals of tokenOut
    function getPrice(address tokenIn, address tokenOut, uint amount) external view returns (uint);

    /// @notice Return price the first poolData.tokenIn against the last poolData.tokenOut in decimals of tokenOut.
    /// @param route Array of pool address, swapper address tokenIn, tokenOut
    /// @param amount Amount of tokenIn. If provide zero then amount is 1.0.
    function getPriceForRoute(PoolData[] memory route, uint amount) external view returns (uint);

    /// @notice Check possibility of swap tokenIn for tokenOut
    /// @param tokenIn Swap input token
    /// @param tokenOut Swap output token
    /// @return Swap route exists
    function isRouteExist(address tokenIn, address tokenOut) external view returns (bool);

    /// @notice Build route for swap. No reverts inside.
    /// @param tokenIn Swap input token
    /// @param tokenOut Swap output token
    /// @return route Array of pools for swap tokenIn to tokenOut. Zero length indicate an error.
    /// @return errorMessage Possible reason why the route was not found. Empty for success routes.
    function buildRoute(
        address tokenIn,
        address tokenOut
    ) external view returns (PoolData[] memory route, string memory errorMessage);

    /// @notice Sell tokenIn for tokenOut
    /// @dev Assume approve on this contract exist
    /// @param tokenIn Swap input token
    /// @param tokenOut Swap output token
    /// @param amount Amount of tokenIn for swap.
    /// @param priceImpactTolerance Price impact tolerance. Must include fees at least. Denominator is 100_000.
    function swap(address tokenIn, address tokenOut, uint amount, uint priceImpactTolerance) external;

    /// @notice Swap by predefined route
    /// @param route Array of pool address, swapper address tokenIn, tokenOut.
    /// TokenIn from first item will be swaped to tokenOut of last .
    /// @param amount Amount of first item tokenIn.
    /// @param priceImpactTolerance Price impact tolerance. Must include fees at least. Denominator is 100_000.
    function swapWithRoute(PoolData[] memory route, uint amount, uint priceImpactTolerance) external;
}
