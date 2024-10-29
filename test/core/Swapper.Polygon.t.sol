// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import "../../chains/PolygonLib.sol";
import "../../src/core/Platform.sol";
import "../../src/core/Swapper.sol";
import "../../src/adapters/UniswapV3Adapter.sol";
import "../../src/adapters/AlgebraAdapter.sol";
import "../../src/core/proxy/Proxy.sol";
import "../../src/adapters/KyberAdapter.sol";
import "../base/chains/PolygonSetup.sol";
import "../../src/adapters/libs/AmmAdapterIdLib.sol";

contract SwapperPolygonTest is Test, PolygonSetup {
    Swapper public swapper;
    UniswapV3Adapter public uniswapV3Adapter;
    AlgebraAdapter public algebraAdapter;
    KyberAdapter public kyberAdapter;

    function setUp() public {
        vm.rollFork(47020000); // Sep-01-2023 03:23:25 PM +UTC

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new Platform()));
        platform = Platform(address(proxy));
        platform.initialize(address(this), "23.11.0-dev");
        proxy = new Proxy();
        proxy.initProxy(address(new Swapper()));
        swapper = Swapper(address(proxy));

        swapper.initialize(address(platform));

        //add AmmAdapterIdLib's id adapter
        uniswapV3Adapter = new UniswapV3Adapter();
        platform.addAmmAdapter(AmmAdapterIdLib.UNISWAPV3, address(uniswapV3Adapter));

        // deploy and init adapters
        proxy = new Proxy();
        proxy.initProxy(address(new UniswapV3Adapter()));
        uniswapV3Adapter = UniswapV3Adapter(address(proxy));
        uniswapV3Adapter.init(address(platform));
        proxy = new Proxy();
        proxy.initProxy(address(new AlgebraAdapter()));
        algebraAdapter = AlgebraAdapter(address(proxy));
        algebraAdapter.init(address(platform));
        proxy = new Proxy();
        proxy.initProxy(address(new KyberAdapter()));
        kyberAdapter = KyberAdapter(address(proxy));
        kyberAdapter.init(address(platform));

        // add routes
        ISwapper.PoolData[] memory pools = new ISwapper.PoolData[](6);
        pools[0] = ISwapper.PoolData({
            pool: PolygonLib.POOL_UNISWAPV3_USDCe_USDT_100,
            ammAdapter: address(uniswapV3Adapter),
            tokenIn: PolygonLib.TOKEN_USDCe,
            tokenOut: PolygonLib.TOKEN_USDT
        });
        pools[1] = ISwapper.PoolData({
            pool: PolygonLib.POOL_UNISWAPV3_USDCe_DAI_100,
            ammAdapter: address(uniswapV3Adapter),
            tokenIn: PolygonLib.TOKEN_DAI,
            tokenOut: PolygonLib.TOKEN_USDCe
        });

        pools[2] = ISwapper.PoolData({
            pool: PolygonLib.POOL_QUICKSWAPV3_USDT_DAI,
            ammAdapter: address(algebraAdapter),
            tokenIn: PolygonLib.TOKEN_USDT,
            tokenOut: PolygonLib.TOKEN_DAI
        });
        pools[3] = ISwapper.PoolData({
            pool: PolygonLib.POOL_QUICKSWAPV3_USDCe_QUICK,
            ammAdapter: address(algebraAdapter),
            tokenIn: PolygonLib.TOKEN_QUICK,
            tokenOut: PolygonLib.TOKEN_USDCe
        });
        pools[4] = ISwapper.PoolData({
            pool: PolygonLib.POOL_QUICKSWAPV3_dQUICK_QUICK,
            ammAdapter: address(algebraAdapter),
            tokenIn: PolygonLib.TOKEN_dQUICK,
            tokenOut: PolygonLib.TOKEN_QUICK
        });

        pools[5] = ISwapper.PoolData({
            pool: PolygonLib.POOL_KYBER_KNC_USDCe,
            ammAdapter: address(kyberAdapter),
            tokenIn: PolygonLib.TOKEN_KNC,
            tokenOut: PolygonLib.TOKEN_USDCe
        });
        swapper.addPools(pools, true);

        deal(PolygonLib.TOKEN_USDCe, address(this), 100002e6);
        IERC20(PolygonLib.TOKEN_USDCe).approve(address(swapper), 100002e6);
        deal(PolygonLib.TOKEN_USDT, address(this), 1002e6);
        IERC20(PolygonLib.TOKEN_USDT).approve(address(swapper), 1002e6);
        deal(PolygonLib.TOKEN_DAI, address(this), 1002e18);
        IERC20(PolygonLib.TOKEN_DAI).approve(address(swapper), 1002e18);
    }

    function testGetPrices() public view {
        uint price = swapper.getPrice(PolygonLib.TOKEN_USDCe, PolygonLib.TOKEN_DAI, 0);
        assertGt(price, 9e17);
        assertLt(price, 11e17);

        price = swapper.getPrice(PolygonLib.TOKEN_DAI, PolygonLib.TOKEN_dQUICK, 0);
        // 20.946161146069675069
        assertGt(price, 1e18);
        assertLt(price, 1e20);

        price = swapper.getPrice(PolygonLib.TOKEN_KNC, PolygonLib.TOKEN_dQUICK, 0);
        // 10.657801141267248159
        assertGt(price, 1e18);
        assertLt(price, 1e20);

        //9.999179532829849850
        price = swapper.getPrice(PolygonLib.TOKEN_USDCe, PolygonLib.TOKEN_DAI, 10e6);
        assertGt(price, 90e17);
        assertLt(price, 110e17);

        price = swapper.getPrice(PolygonLib.TOKEN_USDCe, address(1), 0);
        assertEq(price, 0);
    }

    function testGetPricesForRoute() public view {
        (ISwapper.PoolData[] memory route,) = swapper.buildRoute(PolygonLib.TOKEN_USDCe, PolygonLib.TOKEN_DAI);
        uint price = swapper.getPriceForRoute(route, 0);
        assertGt(price, 9e17);
        assertLt(price, 11e17);

        (route,) = swapper.buildRoute(PolygonLib.TOKEN_DAI, PolygonLib.TOKEN_dQUICK);
        price = swapper.getPriceForRoute(route, 0);
        // 20.946161146069675069
        assertGt(price, 1e18);
        assertLt(price, 1e20);

        (route,) = swapper.buildRoute(PolygonLib.TOKEN_KNC, PolygonLib.TOKEN_dQUICK);
        price = swapper.getPriceForRoute(route, 0);
        // 10.657801141267248159
        assertGt(price, 1e18);
        assertLt(price, 1e20);

        (route,) = swapper.buildRoute(PolygonLib.TOKEN_USDCe, PolygonLib.TOKEN_DAI);
        //9.999179532829849850
        price = swapper.getPriceForRoute(route, 10e6);
        assertGt(price, 90e17);
        assertLt(price, 110e17);
    }

    function testIsRouteExist() public view {
        bool result = swapper.isRouteExist(PolygonLib.TOKEN_USDCe, PolygonLib.TOKEN_DAI);
        assertEq(result, true);
        result = swapper.isRouteExist(PolygonLib.TOKEN_USDCe, address(1));
        assertEq(result, false);
    }

    function testGetAssets() public view {
        assertEq(swapper.assets().length, 6);
        assertEq(swapper.bcAssets().length, 0);
    }

    function testAdaptersGetLiquidityForAmounts() public view {
        uint[] memory amounts = new uint[](2);
        amounts[0] = 10e6;
        amounts[1] = 5e6;
        int24[] memory ticks = new int24[](2);
        ticks[0] = -60;
        ticks[1] = 60;
        (uint liquidity, uint[] memory amountsConsumed) =
            uniswapV3Adapter.getLiquidityForAmounts(PolygonLib.POOL_UNISWAPV3_USDCe_USDT_100, amounts, ticks);
        assertGt(liquidity, 0);
        assertGt(amountsConsumed[0], 0);
        assertGt(amountsConsumed[1], 0);

        (liquidity, amountsConsumed) =
            algebraAdapter.getLiquidityForAmounts(PolygonLib.POOL_QUICKSWAPV3_USDCe_USDT, amounts, ticks);
        assertGt(liquidity, 0);
        assertGt(amountsConsumed[0], 0);
        assertGt(amountsConsumed[1], 0);

        // (uint amount0, uint amount1) = algebraAdapt_getAmountsForLiquidityity(PolygonLib.POOL_QUICKSWAPV3_USDC_USDT, int24 lowerTick, int24 upperTick, uint128 liquidity);

        (liquidity, amountsConsumed) =
            kyberAdapter.getLiquidityForAmounts(PolygonLib.POOL_KYBER_USDCe_USDT, amounts, ticks);
        assertGt(liquidity, 0);
        assertGt(amountsConsumed[0], 0);
        assertGt(amountsConsumed[1], 0);
    }

    function testAdaptersPoolTokens() public view {
        address[] memory tokens;

        tokens = uniswapV3Adapter.poolTokens(PolygonLib.POOL_UNISWAPV3_USDCe_USDT_100);
        assertEq(tokens[0], PolygonLib.TOKEN_USDCe);
        assertEq(tokens[1], PolygonLib.TOKEN_USDT);

        tokens = algebraAdapter.poolTokens(PolygonLib.POOL_QUICKSWAPV3_USDCe_USDT);
        assertEq(tokens[0], PolygonLib.TOKEN_USDCe);
        assertEq(tokens[1], PolygonLib.TOKEN_USDT);

        tokens = kyberAdapter.poolTokens(PolygonLib.POOL_KYBER_USDCe_USDT);
        assertEq(tokens[0], PolygonLib.TOKEN_USDCe);
        assertEq(tokens[1], PolygonLib.TOKEN_USDT);
    }

    function testSwap1Pool() public {
        // uniswap v3
        vm.expectRevert();
        swapper.swap(PolygonLib.TOKEN_USDCe, PolygonLib.TOKEN_USDT, 100000e6, 1); // 0.001%
        swapper.swap(PolygonLib.TOKEN_USDCe, PolygonLib.TOKEN_USDT, 1e6, 1_000); // 1%
    }

    function testSwap2Pools() public {
        // kyber - uniswapv3
        vm.expectRevert();
        swapper.swap(PolygonLib.TOKEN_DAI, PolygonLib.TOKEN_KNC, 1000e18, 1); // 0.001%
        swapper.swap(PolygonLib.TOKEN_DAI, PolygonLib.TOKEN_KNC, 1e18, 1_000); // 1%
    }

    function testSwap4Pools() public {
        // quickswap -> uniswapv3 -> quickswap -> quuickswap
        vm.expectRevert();
        swapper.swap(PolygonLib.TOKEN_USDT, PolygonLib.TOKEN_dQUICK, 100e6, 1); // 0.001%
        swapper.swap(PolygonLib.TOKEN_USDT, PolygonLib.TOKEN_dQUICK, 1e6, 1_000); // 1%
    }

    function testSwapReverts() public {
        // trying to get 0 length path
        vm.expectRevert();
        swapper.swap(address(1), address(2), 1e6, 1_000); // 1%
        // trying to swap less then threshold
        address[] memory tokenIn = new address[](1);
        tokenIn[0] = PolygonLib.TOKEN_USDCe;
        uint[] memory thresholdAmount = new uint[](1);
        thresholdAmount[0] = 10;
        swapper.setThresholds(tokenIn, thresholdAmount);
        uint[] memory newThresholdAmount = new uint[](2);
        newThresholdAmount[0] = 10;
        newThresholdAmount[1] = 5;
        vm.expectRevert(abi.encodeWithSelector(IControllable.IncorrectArrayLength.selector));
        swapper.setThresholds(tokenIn, newThresholdAmount);
        uint threshold = swapper.threshold(PolygonLib.TOKEN_USDCe);
        vm.expectRevert(abi.encodeWithSelector(ISwapper.LessThenThreshold.selector, threshold));
        swapper.swap(PolygonLib.TOKEN_USDCe, PolygonLib.TOKEN_USDT, threshold - 1, 1_000); // 1%
    }

    function testSwapByRoute4Pools() public {
        // quickswap -> uniswapv3 -> quickswap -> quickswap
        (ISwapper.PoolData[] memory route,) = swapper.buildRoute(PolygonLib.TOKEN_USDT, PolygonLib.TOKEN_dQUICK);
        assertEq(route.length, 4);
        swapper.swapWithRoute(route, 1e6, 1_000); // 1%
        ISwapper.PoolData[] memory _route = new ISwapper.PoolData[](0);
        vm.expectRevert(abi.encodeWithSelector(IControllable.IncorrectArrayLength.selector));
        swapper.swapWithRoute(_route, 1e6, 1_000);
    }

    function testSetup() public {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new Platform()));
        platform = Platform(address(proxy));
        platform.initialize(address(this), "23.11.0-dev");
        proxy = new Proxy();
        proxy.initProxy(address(new Swapper()));
        swapper = Swapper(address(proxy));

        swapper.initialize(address(platform));

        // deploy and init adapters
        proxy = new Proxy();
        proxy.initProxy(address(new UniswapV3Adapter()));
        uniswapV3Adapter = UniswapV3Adapter(address(proxy));
        uniswapV3Adapter.init(address(platform));
        proxy = new Proxy();
        proxy.initProxy(address(new AlgebraAdapter()));
        algebraAdapter = AlgebraAdapter(address(proxy));
        algebraAdapter.init(address(platform));
        proxy = new Proxy();
        proxy.initProxy(address(new KyberAdapter()));
        kyberAdapter = KyberAdapter(address(proxy));
        kyberAdapter.init(address(platform));

        // add routes
        ISwapper.PoolData[] memory pools = new ISwapper.PoolData[](1);
        pools[0] = ISwapper.PoolData({
            pool: PolygonLib.POOL_UNISWAPV3_USDCe_USDT_100,
            ammAdapter: address(uniswapV3Adapter),
            tokenIn: PolygonLib.TOKEN_USDCe,
            tokenOut: PolygonLib.TOKEN_USDT
        });
        swapper.addPools(pools, false);
        swapper.removePool(PolygonLib.TOKEN_USDCe);
    }

    function testRequireAddPools() public {
        ISwapper.PoolData[] memory pools = new ISwapper.PoolData[](1);
        pools[0] = ISwapper.PoolData({
            pool: PolygonLib.POOL_UNISWAPV3_USDCe_USDT_100,
            ammAdapter: address(uniswapV3Adapter),
            tokenIn: PolygonLib.TOKEN_USDCe,
            tokenOut: PolygonLib.TOKEN_USDT
        });

        vm.expectRevert(abi.encodeWithSelector(IControllable.AlreadyExist.selector));
        swapper.addPools(pools, false);

        ISwapper.AddPoolData[] memory pools_ = new ISwapper.AddPoolData[](1);
        pools_[0] = ISwapper.AddPoolData({
            pool: PolygonLib.POOL_UNISWAPV3_USDCe_USDT_100,
            ammAdapterId: "123",
            tokenIn: PolygonLib.TOKEN_USDCe,
            tokenOut: PolygonLib.TOKEN_USDT
        });

        vm.expectRevert(abi.encodeWithSelector(ISwapper.UnknownAMMAdapter.selector));
        swapper.addPools(pools_, false);

        pools_[0] = ISwapper.AddPoolData({
            pool: PolygonLib.POOL_UNISWAPV3_USDCe_USDT_100,
            ammAdapterId: AmmAdapterIdLib.UNISWAPV3,
            tokenIn: PolygonLib.TOKEN_USDCe,
            tokenOut: PolygonLib.TOKEN_USDT
        });

        vm.expectRevert(abi.encodeWithSelector(IControllable.AlreadyExist.selector));
        swapper.addPools(pools_, false);
    }

    function testAddRemoveBlueChipsPools() public {
        ISwapper.PoolData[] memory pools = new ISwapper.PoolData[](1);
        pools[0] = ISwapper.PoolData({
            pool: PolygonLib.POOL_UNISWAPV3_USDCe_USDT_100,
            ammAdapter: address(uniswapV3Adapter),
            tokenIn: PolygonLib.TOKEN_USDCe,
            tokenOut: PolygonLib.TOKEN_USDT
        });

        swapper.addBlueChipsPools(pools, false);
        vm.expectRevert(abi.encodeWithSelector(IControllable.AlreadyExist.selector));
        swapper.addBlueChipsPools(pools, false);

        ISwapper.AddPoolData[] memory pools_ = new ISwapper.AddPoolData[](1);
        pools_[0] = ISwapper.AddPoolData({
            pool: PolygonLib.POOL_UNISWAPV3_USDCe_USDT_100,
            ammAdapterId: "123",
            tokenIn: PolygonLib.TOKEN_USDCe,
            tokenOut: PolygonLib.TOKEN_USDT
        });

        vm.expectRevert(abi.encodeWithSelector(ISwapper.UnknownAMMAdapter.selector));
        swapper.addBlueChipsPools(pools_, false);

        pools_[0] = ISwapper.AddPoolData({
            pool: PolygonLib.POOL_UNISWAPV3_USDCe_USDT_100,
            ammAdapterId: AmmAdapterIdLib.UNISWAPV3,
            tokenIn: PolygonLib.TOKEN_USDCe,
            tokenOut: PolygonLib.TOKEN_USDT
        });

        vm.expectRevert(abi.encodeWithSelector(IControllable.AlreadyExist.selector));
        swapper.addBlueChipsPools(pools_, false);

        vm.expectRevert(abi.encodeWithSelector(IControllable.NotExist.selector));
        swapper.removeBlueChipPool(address(1), address(2));

        swapper.removeBlueChipPool(PolygonLib.TOKEN_USDCe, PolygonLib.TOKEN_USDT);
        address pool = swapper.blueChipsPools(PolygonLib.TOKEN_USDCe, PolygonLib.TOKEN_USDT).pool;
        assertEq(pool, address(0));
    }
}
