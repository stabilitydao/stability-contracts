// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {MetaVaultAdapter} from "../../src/adapters/MetaVaultAdapter.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {SonicSetup, SonicConstantsLib, IERC20} from "../base/chains/SonicSetup.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
// import {console} from "forge-std/Test.sol";

contract MetaVaultAdapterUpgrade101Test is SonicSetup {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    uint public constant FORK_BLOCK = 40834789; // Jul-30-2025 04:59:49 AM +UTC

    MetaVaultAdapter public adapter;
    address public multisig;

    constructor() {
        vm.rollFork(FORK_BLOCK);
        _init();

        adapter = MetaVaultAdapter(IPlatform(PLATFORM).ammAdapter(keccak256(bytes(AmmAdapterIdLib.META_VAULT))).proxy);
        multisig = IPlatform(PLATFORM).multisig();

        _upgradePlatform();
    }

    function testSwapsMetaUsdcSmall() public {
        _testSwapsMetaUsdc(10e6);
        _testSwapsMetaUsdc(1e6);
        _testSwapsMetaUsdc(100e6);
    }

    function testSwapsMetaUsdcLarge() public {
        _testSwapsMetaUsdc(100_000e6);
        _testSwapsMetaUsdc(1_000_000e6);
    }

    //    function testSwapsMetaUsdc_Fuzzy() public {
    //        amount = bound(amount, 1e6, 100_0000e6);
    //        _testSwapsMetaUsdc(amount);
    //    }

    function _testSwapsMetaUsdc(uint amount) internal {
        uint snapshot = vm.snapshotState();
        IMetaVault metaVaultUsdc = IMetaVault(SonicConstantsLib.METAVAULT_META_USDC);

        uint got;
        address[] memory vaults = metaVaultUsdc.vaults();
        assertGt(vaults.length, 2);

        // deposit 100 wS to MetaVault and get MetaS on balance
        deal(SonicConstantsLib.TOKEN_USDC, address(this), amount);
        _depositToMetaVault(metaVaultUsdc, amount, address(this));
        uint metaVaultBalance = metaVaultUsdc.balanceOf(address(this));

        // swap 100 MetaUSDC to USDC
        got = _swap(
            SonicConstantsLib.METAVAULT_META_USDC,
            SonicConstantsLib.METAVAULT_META_USDC,
            SonicConstantsLib.TOKEN_USDC,
            metaVaultBalance,
            1_000 // 1% price impact
        );
        vm.roll(block.number + 6);
        assertApproxEqAbs(got, amount, 1, "got all usdc");

        // swap 100 wS to MetaS
        got = _swap(
            SonicConstantsLib.METAVAULT_META_USDC,
            SonicConstantsLib.TOKEN_USDC,
            SonicConstantsLib.METAVAULT_META_USDC,
            got,
            1_000 // 1% price impact
        );
        vm.roll(block.number + 6);
        assertApproxEqAbs(got, metaVaultBalance, 1e14, "got all metaUSDC back");

        vm.revertToState(snapshot);
    }
    //endregion ------------------------------------ Tests for swaps

    //region ------------------------------------ Internal logic
    function _swap(
        address pool,
        address tokenIn,
        address tokenOut,
        uint amount,
        uint priceImpact
    ) internal returns (uint) {
        IERC20(tokenIn).transfer(address(adapter), amount);
        vm.roll(block.number + 6);

        uint balanceWas = IERC20(tokenOut).balanceOf(address(this));
        adapter.swap(pool, tokenIn, tokenOut, address(this), priceImpact);
        return IERC20(tokenOut).balanceOf(address(this)) - balanceWas;
    }
    //endregion ------------------------------------ Internal logic

    //region ------------------------------------ Helper functions
    function _depositToMetaVault(IMetaVault metaVault_, uint amount, address user) internal {
        address[] memory assets = metaVault_.assetsForDeposit();
        uint[] memory amountsMax = new uint[](1);
        amountsMax[0] = amount;

        _dealAndApprove(user, address(metaVault_), assets, amountsMax);

        (,, uint valueOut) = metaVault_.previewDepositAssets(assets, amountsMax);

        vm.prank(user);
        metaVault_.depositAssets(assets, amountsMax, valueOut * 98 / 100, user);

        vm.roll(block.number + 6);
    }

    function _dealAndApprove(address user, address spender, address[] memory assets, uint[] memory amounts) internal {
        for (uint j; j < assets.length; ++j) {
            deal(assets[j], user, amounts[j]);
            vm.prank(user);
            IERC20(assets[j]).approve(spender, amounts[j]);
        }
    }

    function _upgradePlatform() internal {
        // we need to skip 1 day to update the swapper
        // but we cannot simply skip 1 day, because the silo oracle will start to revert with InvalidPrice
        // vm.warp(block.timestamp - 86400);
        rewind(86400);

        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](1);
        address[] memory implementations = new address[](1);

        proxies[0] = platform.ammAdapter(keccak256(bytes(AmmAdapterIdLib.META_VAULT))).proxy;
        implementations[0] = address(new MetaVaultAdapter());

        vm.startPrank(multisig);
        platform.announcePlatformUpgrade("2025.08.0-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }
    //endregion ------------------------------------ Helper functions
}
