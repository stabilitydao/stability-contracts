// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Swapper} from "../../src/core/Swapper.sol";
// import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {AaveV3Adapter} from "../../src/adapters/AaveV3Adapter.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {ERC4626Adapter} from "../../src/adapters/ERC4626Adapter.sol";
import {IAmmAdapter} from "../../src/interfaces/IAmmAdapter.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {Test} from "forge-std/Test.sol";
import {UniswapV3Adapter} from "../../src/adapters/UniswapV3Adapter.sol";
// import {console} from "forge-std/console.sol";

contract AaveV3AdapterTest is Test {
    address public constant PLATFORM = PlasmaConstantsLib.PLATFORM;

    bytes32 public _hash;
    IAmmAdapter public adapter;

    uint internal constant FORK_BLOCK = 6452516; // Nov-17-2025 12:36:59 UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("PLASMA_RPC_URL"), FORK_BLOCK));

        // _upgradePlatform();
    }

    //region ------------------ Tests
    function testSwaps() public {
        _addAdapter();
        _addAdapterErc4626();
        _addAdapterErcUniswapV3();

        ISwapper swapper = ISwapper(IPlatform(PLATFORM).swapper());
        address multisig = IPlatform(PLATFORM).multisig();

        ISwapper.AddPoolData[] memory bcPools = new ISwapper.AddPoolData[](1);
        bcPools[0] = _makePoolData(
            PlasmaConstantsLib.POOL_OKU_TRADE_USDT0_WETH,
            AmmAdapterIdLib.UNISWAPV3,
            PlasmaConstantsLib.TOKEN_WETH,
            PlasmaConstantsLib.TOKEN_USDT0
        );

        ISwapper.AddPoolData[] memory pools = new ISwapper.AddPoolData[](3);
        pools[0] = _makePoolData(
            PlasmaConstantsLib.AAVE_V3_POOL_WETH,
            AmmAdapterIdLib.AAVE_V3,
            PlasmaConstantsLib.AAVE_V3_POOL_WETH,
            PlasmaConstantsLib.TOKEN_WETH
        );
        pools[1] = _makePoolData(
            PlasmaConstantsLib.TOKEN_WAPLAWETH,
            AmmAdapterIdLib.ERC_4626,
            PlasmaConstantsLib.TOKEN_WAPLAWETH,
            PlasmaConstantsLib.TOKEN_WETH
        );
        pools[2] = _makePoolData(
            PlasmaConstantsLib.POOL_OKU_TRADE_USDT0_WETH,
            AmmAdapterIdLib.UNISWAPV3,
            PlasmaConstantsLib.TOKEN_WETH,
            PlasmaConstantsLib.TOKEN_USDT0
        );

        vm.prank(multisig);
        swapper.addPools(pools, false);

        {
            uint snapshotId = vm.snapshotState();
            // ------------------------------- WETH => aPlaWETH
            deal(PlasmaConstantsLib.TOKEN_WETH, address(this), 1e18);

            IERC20(PlasmaConstantsLib.TOKEN_WETH).approve(address(swapper), type(uint).max);
            swapper.swap(PlasmaConstantsLib.TOKEN_WETH, PlasmaConstantsLib.AAVE_V3_POOL_WETH, 1e18, 1000);

            uint balanceAToken = IERC20(PlasmaConstantsLib.AAVE_V3_POOL_WETH).balanceOf(address(this));
            assertApproxEqRel(balanceAToken, 1e18, 1e16, "WETH => aPlaWETH");

            // ------------------------------- aPlaWETH => WETH
            IERC20(PlasmaConstantsLib.AAVE_V3_POOL_WETH).approve(address(swapper), type(uint).max);
            swapper.swap(PlasmaConstantsLib.AAVE_V3_POOL_WETH, PlasmaConstantsLib.TOKEN_WETH, balanceAToken, 0);

            uint finalBalance = IERC20(PlasmaConstantsLib.TOKEN_WETH).balanceOf(address(this));
            assertApproxEqAbs(finalBalance, 1e18, 1, "aPlaWETH => WETH");

            vm.revertToState(snapshotId);
        }

        {
            uint snapshotId = vm.snapshotState();
            // ------------------------------- WETH => waPlaWETH
            deal(PlasmaConstantsLib.TOKEN_WETH, address(this), 1e18);

            IERC20(PlasmaConstantsLib.TOKEN_WETH).approve(address(swapper), type(uint).max);
            swapper.swap(PlasmaConstantsLib.TOKEN_WETH, PlasmaConstantsLib.TOKEN_WAPLAWETH, 1e18, 1000);

            uint balanceWrappedAToken = IERC20(PlasmaConstantsLib.TOKEN_WAPLAWETH).balanceOf(address(this));
            assertApproxEqRel(balanceWrappedAToken, 1e18, 1e16, "WETH => waPlaWETH");

            // ------------------------------- waPlaWETH => WETH
            IERC20(PlasmaConstantsLib.TOKEN_WAPLAWETH).approve(address(swapper), type(uint).max);
            swapper.swap(PlasmaConstantsLib.TOKEN_WAPLAWETH, PlasmaConstantsLib.TOKEN_WETH, balanceWrappedAToken, 0);

            uint finalBalance = IERC20(PlasmaConstantsLib.TOKEN_WETH).balanceOf(address(this));
            assertApproxEqAbs(finalBalance, 1e18, 1, "waPlaWETH => WETH");
            vm.revertToState(snapshotId);
        }
    }

    function testViewMethods() public {
        _addAdapter();

        assertEq(keccak256(bytes(adapter.ammAdapterId())), _hash, "hash");

        uint price = adapter.getPrice(
            PlasmaConstantsLib.AAVE_V3_POOL_USDT0, PlasmaConstantsLib.AAVE_V3_POOL_USDT0, address(0), 1e6
        );
        assertEq(price, 1e6, "getPrice atoken aUSDT0");

        price = adapter.getPrice(
            PlasmaConstantsLib.AAVE_V3_POOL_WETH, PlasmaConstantsLib.AAVE_V3_POOL_WETH, address(0), 1e18
        );
        assertEq(price, 1e18, "getPrice atoken aWETH");

        price = adapter.getPrice(
            PlasmaConstantsLib.AAVE_V3_POOL_WETH,
            PlasmaConstantsLib.TOKEN_WETH,
            PlasmaConstantsLib.AAVE_V3_POOL_WETH,
            1e18
        );
        assertEq(price, 1e18, "getPrice WETH");

        price = adapter.getPrice(
            PlasmaConstantsLib.AAVE_V3_POOL_WETH, PlasmaConstantsLib.AAVE_V3_POOL_WETH, address(0), 1e18
        );
        assertEq(price, 1e18, "atoken=>0");

        price = adapter.getPrice(PlasmaConstantsLib.AAVE_V3_POOL_WETH, PlasmaConstantsLib.TOKEN_WETH, address(0), 1e18);
        assertEq(price, 0, "asset=>0");

        price = adapter.getPrice(
            PlasmaConstantsLib.AAVE_V3_POOL_WETH,
            PlasmaConstantsLib.AAVE_V3_POOL_SUSDE,
            PlasmaConstantsLib.TOKEN_SUSDE,
            1e18
        );
        assertEq(price, 0, "atoken != pool");

        vm.expectRevert("Not supported");
        adapter.getLiquidityForAmounts(address(0), new uint[](2));

        vm.expectRevert("Not supported");
        adapter.getProportions(address(0));

        address[] memory poolTokens = adapter.poolTokens(PlasmaConstantsLib.AAVE_V3_POOL_WETH);
        assertEq(poolTokens.length, 2);
        assertEq(poolTokens[0], PlasmaConstantsLib.TOKEN_WETH, "pool tokens 0");
        assertEq(poolTokens[1], PlasmaConstantsLib.AAVE_V3_POOL_WETH, "pool tokens 1");

        assertEq(adapter.supportsInterface(type(IAmmAdapter).interfaceId), true, "IAmmAdapter");
        assertEq(adapter.supportsInterface(type(IERC165).interfaceId), true, "IERC165");
    }

    function testGetTwaPrice() public {
        _addAdapter();

        vm.expectRevert("Not supported");
        adapter.getTwaPrice(address(0), address(0), address(0), 0, 0);
    }

    //endregion ------------------ Tests

    //region ------------------ Helpers
    function _makePoolData(
        address pool,
        string memory ammAdapterId,
        address tokenIn,
        address tokenOut
    ) internal pure returns (ISwapper.AddPoolData memory) {
        return ISwapper.AddPoolData({pool: pool, ammAdapterId: ammAdapterId, tokenIn: tokenIn, tokenOut: tokenOut});
    }

    function _addAdapter() internal {
        _hash = keccak256(bytes(AmmAdapterIdLib.AAVE_V3));

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new AaveV3Adapter()));

        adapter = IAmmAdapter(address(proxy));
        adapter.init(PLATFORM);

        string memory id = AmmAdapterIdLib.AAVE_V3;
        vm.prank(IPlatform(PLATFORM).multisig());
        IPlatform(PLATFORM).addAmmAdapter(id, address(proxy));
    }

    function _addAdapterErc4626() internal {
        _hash = keccak256(bytes(AmmAdapterIdLib.ERC_4626));

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new ERC4626Adapter()));

        adapter = IAmmAdapter(address(proxy));
        adapter.init(PLATFORM);

        string memory id = AmmAdapterIdLib.ERC_4626;
        vm.prank(IPlatform(PLATFORM).multisig());
        IPlatform(PLATFORM).addAmmAdapter(id, address(proxy));
    }

    function _addAdapterErcUniswapV3() internal {
        _hash = keccak256(bytes(AmmAdapterIdLib.UNISWAPV3));

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new UniswapV3Adapter()));

        adapter = IAmmAdapter(address(proxy));
        adapter.init(PLATFORM);

        string memory id = AmmAdapterIdLib.UNISWAPV3;
        vm.prank(IPlatform(PLATFORM).multisig());
        IPlatform(PLATFORM).addAmmAdapter(id, address(proxy));
    }
    //endregion ------------------ Helpers

    function _upgradePlatform() internal {
        rewind(1 days);

        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](1);
        address[] memory implementations = new address[](1);

        proxies[0] = platform.swapper();
        implementations[0] = address(new Swapper());

        if (platform.pendingPlatformUpgrade().proxies.length != 0) {
            vm.startPrank(platform.multisig());
            platform.cancelUpgrade();
        }

        vm.startPrank(platform.multisig());
        platform.announcePlatformUpgrade("2025.10.01-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }
}
