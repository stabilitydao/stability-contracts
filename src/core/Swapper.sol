// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./base/Controllable.sol";
import "../interfaces/ISwapper.sol";
import "../interfaces/IAmmAdapter.sol";

/// @notice On-chain price quoter and swapper. It works by predefined routes using AMM adapters.
/// @dev Inspired by TetuLiquidator
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
contract Swapper is Controllable, ISwapper {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    //region ----- Constants -----

    /// @dev Version of Swapper implementation
    string public constant VERSION = "1.0.0";

    uint public constant ROUTE_LENGTH_MAX = 5;

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.Swapper")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant SWAPPER_STORAGE_LOCATION =
        0xa3f85328863358c70a5d8558b355ddce3bfd90131b6ba971b451f8def7c6e700;

    //endregion ----- Constants -----

    //region ----- Storage -----

    /// @custom:storage-location erc7201:stability.Swapper
    struct SwapperStorage {
        mapping(address tokenIn => PoolData) pools;
        mapping(address tokenIn => mapping(address tokenOut => PoolData)) blueChipsPools;
        /// @inheritdoc ISwapper
        mapping(address token => uint minAmountToSwap) threshold;
        /// @dev Assets list.
        EnumerableSet.AddressSet _assets;
        /// @dev Blue Chip Assets list.
        EnumerableSet.AddressSet _bcAssets;
    }

    //endregion -- Storage -----

    function initialize(address platform_) public initializer {
        __Controllable_init(platform_);
    }

    //region ----- Restricted actions -----

    /// @inheritdoc ISwapper
    function addPools(PoolData[] memory pools_, bool rewrite) external onlyOperator {
        SwapperStorage storage $ = _getStorage();
        uint len = pools_.length;
        // nosemgrep
        for (uint i; i < len; ++i) {
            PoolData memory pool = pools_[i];
            // nosemgrep
            if ($.pools[pool.tokenIn].pool != address(0) && !rewrite) {
                revert AlreadyExist();
            }
            $.pools[pool.tokenIn] = pool;
            bool assetAdded = $._assets.add(pool.tokenIn);
            emit PoolAdded(pool, assetAdded);
        }
    }

    /// @inheritdoc ISwapper
    function addPools(AddPoolData[] memory pools_, bool rewrite) external onlyOperator {
        SwapperStorage storage $ = _getStorage();
        uint len = pools_.length;
        // nosemgrep
        for (uint i; i < len; ++i) {
            //slither-disable-next-line uninitialized-local
            PoolData memory poolData;
            poolData.pool = pools_[i].pool;
            poolData.tokenIn = pools_[i].tokenIn;
            poolData.tokenOut = pools_[i].tokenOut;
            //slither-disable-next-line calls-loop
            poolData.ammAdapter = IPlatform(platform()).ammAdapter(keccak256(bytes(pools_[i].ammAdapterId))).proxy;
            if (poolData.ammAdapter == address(0)) {
                revert UnknownAMMAdapter();
            }
            // nosemgrep
            if ($.pools[poolData.tokenIn].pool != address(0) && !rewrite) {
                revert AlreadyExist();
            }
            $.pools[poolData.tokenIn] = poolData;
            bool assetAdded = $._assets.add(poolData.tokenIn);
            emit PoolAdded(poolData, assetAdded);
        }
    }

    function removePool(address token) external onlyOperator {
        SwapperStorage storage $ = _getStorage();
        delete $.pools[token];
        //slither-disable-next-line unused-return
        $._assets.remove(token);
        emit PoolRemoved(token);
    }

    /// @inheritdoc ISwapper
    function addBlueChipsPools(PoolData[] memory pools_, bool rewrite) external onlyOperator {
        SwapperStorage storage $ = _getStorage();
        uint len = pools_.length;
        // nosemgrep
        for (uint i; i < len; ++i) {
            PoolData memory pool = pools_[i];
            // nosemgrep
            if ($.blueChipsPools[pool.tokenIn][pool.tokenOut].pool != address(0) && !rewrite) {
                revert AlreadyExist();
            }
            $.blueChipsPools[pool.tokenIn][pool.tokenOut] = pool;
            $.blueChipsPools[pool.tokenOut][pool.tokenIn] = pool;
            _addBcAsset(pool.tokenIn);
            _addBcAsset(pool.tokenOut);
            emit BlueChipAdded(pool);
        }
    }

    /// @inheritdoc ISwapper
    function addBlueChipsPools(AddPoolData[] memory pools_, bool rewrite) external onlyOperator {
        SwapperStorage storage $ = _getStorage();
        uint len = pools_.length;
        // nosemgrep
        for (uint i; i < len; ++i) {
            //slither-disable-next-line uninitialized-local
            PoolData memory poolData;
            poolData.pool = pools_[i].pool;
            poolData.tokenIn = pools_[i].tokenIn;
            poolData.tokenOut = pools_[i].tokenOut;
            //slither-disable-next-line calls-loop
            poolData.ammAdapter = IPlatform(platform()).ammAdapter(keccak256(bytes(pools_[i].ammAdapterId))).proxy;
            if (poolData.ammAdapter == address(0)) {
                revert UnknownAMMAdapter();
            }
            // nosemgrep
            if ($.blueChipsPools[poolData.tokenIn][poolData.tokenOut].pool != address(0) && !rewrite) {
                revert AlreadyExist();
            }
            $.blueChipsPools[poolData.tokenIn][poolData.tokenOut] = poolData;
            $.blueChipsPools[poolData.tokenOut][poolData.tokenIn] = poolData;
            _addBcAsset(poolData.tokenIn);
            _addBcAsset(poolData.tokenOut);
            emit BlueChipAdded(poolData);
        }
    }

    function removeBlueChipPool(address tokenIn, address tokenOut) external onlyOperator {
        SwapperStorage storage $ = _getStorage();
        delete $.blueChipsPools[tokenIn][tokenOut];
        if (!$._bcAssets.remove(tokenIn)) {
            revert NotExist();
        }
        // do not remove tokenOut, assume tha tokenIn is the main target for the removing
        emit BlueChipPoolRemoved(tokenIn, tokenOut);
    }

    /// @inheritdoc ISwapper
    function setThresholds(address[] memory tokenIn, uint[] memory thresholdAmount) external onlyOperator {
        SwapperStorage storage $ = _getStorage();
        uint tokenInLen = tokenIn.length;
        uint thresholdAmountLen = thresholdAmount.length;
        if (tokenInLen != thresholdAmountLen) {
            revert IControllable.IncorrectArrayLength();
        }
        // nosemgrep
        for (uint i = 0; i < tokenInLen; ++i) {
            $.threshold[tokenIn[i]] = thresholdAmount[i];
        }
        emit ThresholdChanged(tokenIn, thresholdAmount);
    }

    //endregion -- Restricted actions ----

    //region ----- User actions -----

    /// @dev Sell tokenIn for tokenOut. Assume approve on this contract exist.
    function swap(address tokenIn, address tokenOut, uint amount, uint priceImpactTolerance) external {
        SwapperStorage storage $ = _getStorage();
        (PoolData[] memory route, string memory errorMessage) = buildRoute(tokenIn, tokenOut);
        if (route.length == 0) {
            revert(errorMessage);
        }
        uint thresholdTokenIn = $.threshold[tokenIn];
        if (amount < thresholdTokenIn) {
            revert LessThenThreshold(thresholdTokenIn);
        }
        _swap(route, amount, priceImpactTolerance);
    }

    /// @inheritdoc ISwapper
    function swapWithRoute(PoolData[] memory route, uint amount, uint priceImpactTolerance) external {
        _swap(route, amount, priceImpactTolerance);
    }

    //endregion -- User actions -----

    //region ----- View functions -----

    /// @inheritdoc ISwapper
    function assets() external view returns (address[] memory) {
        SwapperStorage storage $ = _getStorage();
        return $._assets.values();
    }

    /// @inheritdoc ISwapper
    function bcAssets() external view returns (address[] memory) {
        SwapperStorage storage $ = _getStorage();
        return $._bcAssets.values();
    }

    /// @inheritdoc ISwapper
    function allAssets() external view returns (address[] memory) {
        SwapperStorage storage $ = _getStorage();
        address[] memory __bcAssets = $._bcAssets.values();
        uint bcAssetsLen = __bcAssets.length;
        address[] memory __assets = $._assets.values();
        uint assetsLen = __assets.length;
        uint total = bcAssetsLen;
        uint i;
        for (; i < assetsLen; ++i) {
            if (!$._bcAssets.contains(__assets[i])) {
                ++total;
            }
        }
        address[] memory _allAssets = new address[](total);
        // nosemgrep
        for (i = 0; i < bcAssetsLen; ++i) {
            _allAssets[i] = __bcAssets[i];
        }
        // nosemgrep
        for (uint k; k < assetsLen; ++k) {
            if (!$._bcAssets.contains(__assets[k])) {
                _allAssets[i] = __assets[k];
                ++i;
            }
        }

        return _allAssets;
    }

    /// @inheritdoc ISwapper
    function getPrice(address tokenIn, address tokenOut, uint amount) external view returns (uint) {
        //slither-disable-next-line unused-return
        (PoolData[] memory route,) = buildRoute(tokenIn, tokenOut);
        if (route.length == 0) {
            return 0;
        }
        uint price;
        if (amount != 0) {
            price = amount;
        } else {
            price = 10 ** IERC20Metadata(tokenIn).decimals();
        }
        uint len = route.length;
        // nosemgrep
        for (uint i; i < len; ++i) {
            PoolData memory data = route[i];
            //slither-disable-next-line calls-loop
            price = IAmmAdapter(data.ammAdapter).getPrice(data.pool, data.tokenIn, data.tokenOut, price);
        }
        return price;
    }

    /// @inheritdoc ISwapper
    function getPriceForRoute(PoolData[] memory route, uint amount) external view returns (uint) {
        uint price;
        if (amount != 0) {
            price = amount;
        } else {
            price = 10 ** IERC20Metadata(route[0].tokenIn).decimals();
        }
        uint len = route.length;
        // nosemgrep
        for (uint i; i < len; ++i) {
            PoolData memory data = route[i];
            //slither-disable-next-line calls-loop
            price = IAmmAdapter(data.ammAdapter).getPrice(data.pool, data.tokenIn, data.tokenOut, price);
        }
        return price;
    }

    /// @inheritdoc ISwapper
    function isRouteExist(address tokenIn, address tokenOut) external view returns (bool) {
        //slither-disable-next-line unused-return
        (PoolData[] memory route,) = buildRoute(tokenIn, tokenOut);
        return route.length != 0;
    }

    /// @inheritdoc ISwapper
    function buildRoute(
        address tokenIn,
        address tokenOut
    ) public view override returns (PoolData[] memory route, string memory errorMessage) {
        SwapperStorage storage $ = _getStorage();
        route = new PoolData[](ROUTE_LENGTH_MAX);

        // --- BLUE CHIPS for in/out
        // in case that we try to liquidate blue chips use bc lps directly
        PoolData memory poolDataBC = $.blueChipsPools[tokenIn][tokenOut];
        if (poolDataBC.pool != address(0)) {
            poolDataBC.tokenIn = tokenIn;
            poolDataBC.tokenOut = tokenOut;
            route[0] = poolDataBC;
            return (_cutRoute(route, 1), "");
        }

        // --- POOL for in
        // find the best Pool for token IN
        PoolData memory poolDataIn = $.pools[tokenIn];
        if (poolDataIn.pool == address(0)) {
            return (_cutRoute(route, 0), "Swapper: Not found pool for tokenIn");
        }

        route[0] = poolDataIn;
        // if the best Pool for token IN a pair with token OUT token we complete the route
        if (poolDataIn.tokenOut == tokenOut) {
            return (_cutRoute(route, 1), "");
        }

        // --- BC for POOL_in
        // if we able to swap opposite token to a blue chip it is the cheaper way to liquidate
        poolDataBC = $.blueChipsPools[poolDataIn.tokenOut][tokenOut];
        if (poolDataBC.pool != address(0)) {
            poolDataBC.tokenIn = poolDataIn.tokenOut;
            poolDataBC.tokenOut = tokenOut;
            route[1] = poolDataBC;
            return (_cutRoute(route, 2), "");
        }

        // --- POOL for out
        // find the largest pool for token out
        PoolData memory poolDataOut = $.pools[tokenOut];
        if (poolDataOut.pool == address(0)) {
            return (_cutRoute(route, 0), "Swapper: Not found pool for tokenOut");
        }

        // need to swap directions for tokenOut pool
        (poolDataOut.tokenIn, poolDataOut.tokenOut) = (poolDataOut.tokenOut, poolDataOut.tokenIn);

        // if the largest pool for tokenOut contains tokenIn it is the best way
        if (tokenIn == poolDataOut.tokenIn) {
            route[0] = poolDataOut;
            return (_cutRoute(route, 1), "");
        }

        // if we can swap between largest pools the route is ended
        if (poolDataIn.tokenOut == poolDataOut.tokenIn) {
            route[1] = poolDataOut;
            return (_cutRoute(route, 2), "");
        }

        // --- BC for POOL_out
        // if we able to swap opposite token to a blue chip it is the cheaper way to liquidate
        poolDataBC = $.blueChipsPools[poolDataIn.tokenOut][poolDataOut.tokenIn];
        if (poolDataBC.pool != address(0)) {
            poolDataBC.tokenIn = poolDataIn.tokenOut;
            poolDataBC.tokenOut = poolDataOut.tokenIn;
            route[1] = poolDataBC;
            route[2] = poolDataOut;
            return (_cutRoute(route, 3), "");
        }

        // ------------------------------------------------------------------------
        //                      RECURSIVE PART
        // We don't have 1-2 pair routes. Need to find pairs for pairs.
        // This part could be build as recursion but for reduce complexity and safe gas was not.
        // ------------------------------------------------------------------------

        // --- POOL2 for in
        PoolData memory poolDataIn2 = $.pools[poolDataIn.tokenOut];
        if (poolDataIn2.pool == address(0)) {
            return (_cutRoute(route, 0), "L: Not found pool for tokenIn2");
        }

        route[1] = poolDataIn2;
        if (poolDataIn2.tokenOut == tokenOut) {
            return (_cutRoute(route, 2), "");
        }

        if (poolDataIn2.tokenOut == poolDataOut.tokenIn) {
            route[2] = poolDataOut;
            return (_cutRoute(route, 3), "");
        }

        // --- BC for POOL2_in
        poolDataBC = $.blueChipsPools[poolDataIn2.tokenOut][tokenOut];
        if (poolDataBC.pool != address(0)) {
            poolDataBC.tokenIn = poolDataIn2.tokenOut;
            poolDataBC.tokenOut = tokenOut;
            route[2] = poolDataBC;
            return (_cutRoute(route, 3), "");
        }

        // --- POOL2 for out
        // find the largest pool for token out
        PoolData memory poolDataOut2 = $.pools[poolDataOut.tokenIn];
        if (poolDataOut2.pool == address(0)) {
            return (_cutRoute(route, 0), "L: Not found pool for tokenOut2");
        }

        // need to swap directions for tokenOut2 pool
        (poolDataOut2.tokenIn, poolDataOut2.tokenOut) = (poolDataOut2.tokenOut, poolDataOut2.tokenIn);

        // if we can swap between largest pools the route is ended
        if (poolDataIn.tokenOut == poolDataOut2.tokenIn) {
            route[1] = poolDataOut2;
            route[2] = poolDataOut;
            return (_cutRoute(route, 3), "");
        }

        if (poolDataIn2.tokenOut == poolDataOut2.tokenIn) {
            route[2] = poolDataOut2;
            route[3] = poolDataOut;
            return (_cutRoute(route, 4), "");
        }

        // --- BC for POOL2_out

        // token OUT pool can be paired with BC pool with token IN
        poolDataBC = $.blueChipsPools[tokenIn][poolDataOut2.tokenIn];
        if (poolDataBC.pool != address(0)) {
            poolDataBC.tokenIn = tokenIn;
            poolDataBC.tokenOut = poolDataOut2.tokenIn;
            route[0] = poolDataBC;
            route[1] = poolDataOut2;
            route[2] = poolDataOut;
            return (_cutRoute(route, 3), "");
        }

        poolDataBC = $.blueChipsPools[poolDataIn.tokenOut][poolDataOut2.tokenIn];
        if (poolDataBC.pool != address(0)) {
            poolDataBC.tokenIn = poolDataIn.tokenOut;
            poolDataBC.tokenOut = poolDataOut2.tokenIn;
            route[1] = poolDataBC;
            route[2] = poolDataOut2;
            route[3] = poolDataOut;
            return (_cutRoute(route, 4), "");
        }

        poolDataBC = $.blueChipsPools[poolDataIn2.tokenOut][poolDataOut2.tokenIn];
        if (poolDataBC.pool != address(0)) {
            poolDataBC.tokenIn = poolDataIn2.tokenOut;
            poolDataBC.tokenOut = poolDataOut2.tokenIn;
            route[2] = poolDataBC;
            route[3] = poolDataOut2;
            route[4] = poolDataOut;
            return (_cutRoute(route, 5), "");
        }

        // We are not handling other cases such as:
        // - If a token has liquidity with specific token
        //   and this token also has liquidity only with specific token.
        //   This case never exist but could be implemented if requires.
        return (_cutRoute(route, 0), "Swapper: swap path not found");
    }

    /// @inheritdoc ISwapper
    function threshold(address token) external view returns (uint threshold_) {
        SwapperStorage storage $ = _getStorage();
        threshold_ = $.threshold[token];
    }

    /// @inheritdoc ISwapper
    function blueChipsPools(address tokenIn, address tokenOut) external view returns (PoolData memory poolData) {
        SwapperStorage storage $ = _getStorage();
        poolData = $.blueChipsPools[tokenIn][tokenOut];
    }

    //endregion -- View functions -----

    //region ----- Internal logic -----

    //slither-disable-next-line reentrancy-events
    function _swap(PoolData[] memory route, uint amount, uint priceImpactTolerance) internal {
        if (route.length == 0) {
            revert IControllable.IncorrectArrayLength();
        }
        uint routeLength = route.length;
        // nosemgrep
        for (uint i; i < routeLength; i++) {
            PoolData memory data = route[i];

            // if it is the first step send tokens to the swapper from the current contract
            if (i == 0) {
                IERC20(data.tokenIn).safeTransferFrom(msg.sender, data.ammAdapter, amount);
            }
            address recipient;
            // if it is not the last step of the route send to the next swapper
            if (i != routeLength - 1) {
                recipient = route[i + 1].ammAdapter;
            } else {
                // if it is the last step need to send to the sender
                recipient = msg.sender;
            }

            IAmmAdapter(data.ammAdapter).swap(data.pool, data.tokenIn, data.tokenOut, recipient, priceImpactTolerance);
        }

        emit Swap(route[0].tokenIn, route[routeLength - 1].tokenOut, amount);
    }

    function _cutRoute(PoolData[] memory route, uint length) internal pure returns (PoolData[] memory) {
        PoolData[] memory result = new PoolData[](length);
        // nosemgrep
        for (uint i; i < length; ++i) {
            result[i] = route[i];
        }
        return result;
    }

    function _addBcAsset(address asset) internal {
        SwapperStorage storage $ = _getStorage();
        if (!$._bcAssets.contains(asset)) {
            //slither-disable-next-line unused-return
            $._bcAssets.add(asset);
        }
    }

    function _getStorage() private pure returns (SwapperStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := SWAPPER_STORAGE_LOCATION
        }
    }

    //endregion ----- Internal logic -----
}
