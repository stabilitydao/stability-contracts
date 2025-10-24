// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

// import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SolidlyAdapter} from "../../src/adapters/SolidlyAdapter.sol";
import {IAmmAdapter} from "../../src/interfaces/IAmmAdapter.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract SolidlyAdapterSonicTest is Test {
    uint public constant FORK_BLOCK = 51713531; // Oct-24-2025 03:31:29 AM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public constant POOL_SHADOW_USDC_ASONUSDC = 0x47ffFa06Eeeef596d46cF7d58C3856A751eA68eD;
    IAmmAdapter public _adapter;
    bytes32 public _hash;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
    }

    function testViewMethods() public {
        _upgradePlatform(); // _addAdapter();

        assertEq(keccak256(bytes(_adapter.ammAdapterId())), _hash, "adapter id matches");

        uint[] memory amounts = new uint[](2);
        amounts[0] = 10e6;
        amounts[1] = 10e18;
        (uint liquidity, uint[] memory amountsConsumed) =
            _adapter.getLiquidityForAmounts(SonicConstantsLib.POOL_SHADOW_STBL_USDC, amounts);

        assertGt(liquidity, 0, "liquidity > 0");
        assertGt(amountsConsumed[0], 0, "amountsConsumed[0] > 0");
        assertGt(amountsConsumed[1], 0, "amountsConsumed[1] > 0");
        amounts[1] = 500e18;
        _adapter.getLiquidityForAmounts(SonicConstantsLib.POOL_SHADOW_STBL_USDC, amounts);
        amounts[1] = 1000;
        _adapter.getLiquidityForAmounts(SonicConstantsLib.POOL_SHADOW_STBL_USDC, amounts);

        // ~0.1 USDC for 1 STBL at this block
        uint price = _adapter.getPrice(
            SonicConstantsLib.POOL_SHADOW_STBL_USDC, SonicConstantsLib.TOKEN_STBL, SonicConstantsLib.TOKEN_USDC, 1e18
        );
        assertGt(price, 0.1e6, "price > 0.1 USDC");
        assertLt(price, 0.2e6, "price < 0.2 USDC");

        uint[] memory props = _adapter.getProportions(SonicConstantsLib.POOL_SHADOW_STBL_USDC);
        assertEq(props[0], 50e16, "props[0] is always 50% in NOT stable pool");

        // ~48.79% / 51.21%
        props = _adapter.getProportions(POOL_SHADOW_USDC_ASONUSDC);
        assertApproxEqAbs(props[0], 48.8e16, 1e14, "props[0] ~ 48.79");

        _adapter.poolTokens(SonicConstantsLib.POOL_SHADOW_STBL_USDC);

        assertEq(_adapter.supportsInterface(type(IAmmAdapter).interfaceId), true);
        assertEq(_adapter.supportsInterface(type(IERC165).interfaceId), true);
    }

    function testSwaps() public {
        _upgradePlatform(); // _addAdapter();

        deal(SonicConstantsLib.TOKEN_USDC, address(_adapter), 1000e6);
        _adapter.swap(
            SonicConstantsLib.POOL_SHADOW_STBL_USDC,
            SonicConstantsLib.TOKEN_USDC,
            SonicConstantsLib.TOKEN_STBL,
            address(this),
            10_000
        );
        uint out = IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(address(this));
        assertEq(out, 5496241215674524771851);

        deal(SonicConstantsLib.TOKEN_USDC, address(_adapter), 100_000e6);

        vm.expectRevert(bytes("!PRICE 47721"));
        _adapter.swap(
            SonicConstantsLib.POOL_SHADOW_STBL_USDC,
            SonicConstantsLib.TOKEN_USDC,
            SonicConstantsLib.TOKEN_STBL,
            address(this),
            10_000
        );
    }

    function testSolidlyAdapter() external {}

    function _makePoolData(
        address pool,
        string memory ammAdapterId,
        address tokenIn,
        address tokenOut
    ) internal pure returns (ISwapper.AddPoolData memory) {
        return ISwapper.AddPoolData({pool: pool, ammAdapterId: ammAdapterId, tokenIn: tokenIn, tokenOut: tokenOut});
    }

    function _addAdapter() internal {
        _hash = keccak256(bytes(AmmAdapterIdLib.SOLIDLY));
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new SolidlyAdapter()));
        _adapter = IAmmAdapter(address(proxy));
        _adapter.init(PLATFORM);
        string memory id = AmmAdapterIdLib.SOLIDLY;
        vm.prank(IPlatform(PLATFORM).multisig());
        IPlatform(PLATFORM).addAmmAdapter(id, address(proxy));
    }

    function _upgradePlatform() internal {
        address multisig = IPlatform(PLATFORM).multisig();

        // we need to skip 1 day to update the swapper
        // but we cannot simply skip 1 day, because the silo oracle will start to revert with InvalidPrice
        // vm.warp(block.timestamp - 86400);
        rewind(86400);

        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](1);
        address[] memory implementations = new address[](1);

        _hash = keccak256(bytes(AmmAdapterIdLib.SOLIDLY));
        _adapter = IAmmAdapter(platform.ammAdapter(_hash).proxy);
        proxies[0] = address(_adapter);
        implementations[0] = address(new SolidlyAdapter());

        vm.startPrank(multisig);
        platform.cancelUpgrade();

        vm.startPrank(multisig);
        platform.announcePlatformUpgrade("2025.08.0-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }
}
