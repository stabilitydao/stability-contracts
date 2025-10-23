// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {SolidlyAdapter} from "../../src/adapters/SolidlyAdapter.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";

contract SolidlyAdapterUpgrade414SonicTest is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    uint public constant FORK_BLOCK = 51622705; // Oct-23-2025 06:32:10 AM +UTC

    SolidlyAdapter public adapter;
    address public multisig;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        adapter = SolidlyAdapter(IPlatform(PLATFORM).ammAdapter(keccak256(bytes(AmmAdapterIdLib.SOLIDLY))).proxy);
        multisig = IPlatform(PLATFORM).multisig();

        _upgradePlatform();
    }

    //region ------------------------------------ Tests
    function testGetTwaSqrtPrice() public view {
        uint price = adapter.getPrice(SonicConstantsLib.POOL_SHADOW_STBL_USDC, SonicConstantsLib.TOKEN_STBL, SonicConstantsLib.TOKEN_USDC, 1e18);
        uint twaPrice = adapter.getTwaPrice(SonicConstantsLib.POOL_SHADOW_STBL_USDC, SonicConstantsLib.TOKEN_STBL, SonicConstantsLib.TOKEN_USDC, 1e18, 1);

        assertApproxEqAbs(price, twaPrice, price * 3 / 100, "current price ~ twa price");
        assertNotEq(price, twaPrice, "current price != twa price");

        // console.log(price, twaPrice);
    }

    function testGetTwaSqrtPriceZeroPeriod() public view {
        uint price = adapter.getPrice(SonicConstantsLib.POOL_SHADOW_STBL_USDC, SonicConstantsLib.TOKEN_STBL, SonicConstantsLib.TOKEN_USDC, 1e18);
        uint twaPrice = adapter.getTwaPrice(SonicConstantsLib.POOL_SHADOW_STBL_USDC, SonicConstantsLib.TOKEN_STBL, SonicConstantsLib.TOKEN_USDC, 1e18, 0);

        assertEq(price, twaPrice, "current price == twa price");
    }

    //endregion ------------------------------------ Tests

    //region ------------------------------------ Helper functions
    function _upgradePlatform() internal {
        // we need to skip 1 day to update the swapper
        // but we cannot simply skip 1 day, because the silo oracle will start to revert with InvalidPrice
        // vm.warp(block.timestamp - 86400);
        rewind(86400);

        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](1);
        address[] memory implementations = new address[](1);

        proxies[0] = platform.ammAdapter(keccak256(bytes(AmmAdapterIdLib.SOLIDLY))).proxy;
        implementations[0] = address(new SolidlyAdapter());

        vm.startPrank(multisig);
        platform.cancelUpgrade();

        vm.startPrank(multisig);
        platform.announcePlatformUpgrade("2025.08.0-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }
    //endregion ------------------------------------ Helper functions
}