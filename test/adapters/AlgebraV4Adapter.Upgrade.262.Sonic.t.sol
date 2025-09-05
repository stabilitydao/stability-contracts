// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {ICAmmAdapter, IAmmAdapter} from "../../src/interfaces/ICAmmAdapter.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {AlgebraV4Adapter, AmmAdapterIdLib} from "../../src/adapters/AlgebraV4Adapter.sol";
import {console, Test} from "forge-std/Test.sol";

contract AlgebraV4AdapterUpgrade262SonicTest is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    uint public constant FORK_BLOCK = 43911991; // Aug-21-2025 04:58:57 AM +UTC

    IFactory public factory;
    address public multisig;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        factory = IFactory(IPlatform(PLATFORM).factory());
        multisig = IPlatform(PLATFORM).multisig();

        _upgradePlatform();
    }

    /// @dev #262: getPriceForRoute(bUSDC.e-20 => wstkscUSD) returned 0.010106 instead of 0.001
    function testGetPriceForRouteBUsdcE20ToWstkscUsd() public view {
        ISwapper swapper = ISwapper(IPlatform(PLATFORM).swapper());

        uint price0;
        uint price1;
        {
            bytes32 _hash = keccak256(bytes(AmmAdapterIdLib.ERC_4626));
            ISwapper.PoolData[] memory routes = new ISwapper.PoolData[](1);
            routes[0] = ISwapper.PoolData({
                pool: SonicConstantsLib.TOKEN_bUSDCe20,
                ammAdapter: IPlatform(PLATFORM).ammAdapter(_hash).proxy,
                tokenIn: SonicConstantsLib.TOKEN_bUSDCe20,
                tokenOut: SonicConstantsLib.TOKEN_wstkscUSD
            });
            price0 = swapper.getPriceForRoute(routes, 1e6);
        }

        {
            bytes32 _hash = keccak256(bytes(AmmAdapterIdLib.ALGEBRA_V4));
            ISwapper.PoolData[] memory routes = new ISwapper.PoolData[](1);
            routes[0] = ISwapper.PoolData({
                pool: SonicConstantsLib.POOL_SWAPX_CL_bUSDCe20_wstkscUSD,
                ammAdapter: IPlatform(PLATFORM).ammAdapter(_hash).proxy,
                tokenIn: SonicConstantsLib.TOKEN_bUSDCe20,
                tokenOut: SonicConstantsLib.TOKEN_wstkscUSD
            });
            price1 = swapper.getPriceForRoute(routes, 1e6);
        }

        assertNotEq(price0, 0, "ERC4626 returns not zero price");

        // Prices doesn't match exactly: 1030 != 1026
        assertApproxEqAbs(price1, price0, 5, "AlgebraV4 returns expected price");
    }

    //region --------------------------------- Helpers
    function _upgradePlatform() internal {
        // we need to skip 1 day to update the swapper
        // but we cannot simply skip 1 day, because the silo oracle will start to revert with InvalidPrice
        // vm.warp(block.timestamp - 86400);
        rewind(86400);

        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](1);
        address[] memory implementations = new address[](1);

        proxies[0] = platform.ammAdapter(keccak256(bytes(AmmAdapterIdLib.ALGEBRA_V4))).proxy;
        implementations[0] = address(new AlgebraV4Adapter());

        vm.startPrank(multisig);
        platform.announcePlatformUpgrade("2025.08.21-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }
    //endregion --------------------------------- Helpers
}
