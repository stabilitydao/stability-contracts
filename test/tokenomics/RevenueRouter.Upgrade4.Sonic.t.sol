// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {RevenueRouter, IRevenueRouter, IERC20} from "../../src/tokenomics/RevenueRouter.sol";
import {IControllable} from "../../src/core/Platform.sol";
import {IVault, IStrategy} from "../../src/interfaces/IVault.sol";

contract RevenueRouterUpgrade4TestSonic is Test {
    uint public constant FORK_BLOCK = 51340000; // Oct-20-2025 06:57:22 PM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public multisig;
    IRevenueRouter public revenueRouter;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        multisig = IPlatform(PLATFORM).multisig();
        revenueRouter = IRevenueRouter(IPlatform(PLATFORM).revenueRouter());
        _upgradeRevenueRouter();
    }

    function testUpgraded() public {
        address vault1 = 0x709833e5B4B98aAb812d175510F94Bc91CFABD89;
        address asset1 = SonicConstantsLib.TOKEN_STS;

        // no vaults for process
        vm.expectRevert(IRevenueRouter.CantProcessAction.selector);
        revenueRouter.processAccumulatedVaults(50);

        address[] memory assetsAccumulated = revenueRouter.assetsAccumulated();
        assertEq(assetsAccumulated.length, 0);

        // do HardWork
        IStrategy strategy1 = IVault(vault1).strategy();
        vm.prank(vault1);
        strategy1.doHardWork();
        vm.roll(block.number + 6);

        // test partial withdraw
        {
            uint vaultBalanceWas = IERC20(vault1).balanceOf(address(revenueRouter));
            uint assetBalanceWas = IERC20(asset1).balanceOf(address(revenueRouter));
            //console.log(vaultBalanceWas / 1e18);
            //console.log(assetBalanceWas / 1e18);
            revenueRouter.processAccumulatedVaults(50, 10000 * 1e18);
            vm.roll(block.number + 6);
            revenueRouter.processAccumulatedVaults(50);
            vm.roll(block.number + 6);
            uint balanceAfter = IERC20(vault1).balanceOf(address(revenueRouter));
            uint assetBalanceAfter = IERC20(asset1).balanceOf(address(revenueRouter));
            assertEq(balanceAfter, vaultBalanceWas - 20e21);
            assertGt(assetBalanceAfter, assetBalanceWas);
            //console.log('vault balance after', balanceAfter / 1e18);
            //console.log('asset balance after', assetBalanceAfter / 1e18);
            assetsAccumulated = revenueRouter.assetsAccumulated();
            assertEq(assetsAccumulated.length, 1);
            assertEq(assetsAccumulated[0], asset1);
        }

        // test buy-back without setup
        vm.expectRevert(IControllable.IncorrectMsgSender.selector);
        revenueRouter.processAccumulatedAssets(50);
        vm.expectRevert(IRevenueRouter.CantProcessAction.selector);
        vm.prank(multisig);
        revenueRouter.processAccumulatedAssets(50);

        // setup buy-backs
        {
            address[] memory assets = new address[](1);
            assets[0] = asset1;
            uint[] memory minAmounts = new uint[](1);
            minAmounts[0] = 10e18;
            vm.expectRevert(IControllable.NotOperator.selector);
            revenueRouter.setMinSwapAmounts(assets, minAmounts);
            vm.prank(multisig);
            revenueRouter.setMinSwapAmounts(assets, minAmounts);
            uint[] memory maxAmounts = new uint[](1);
            maxAmounts[0] = 1000e18;
            vm.expectRevert(IControllable.NotOperator.selector);
            revenueRouter.setMaxSwapAmounts(assets, maxAmounts);
            vm.prank(multisig);
            revenueRouter.setMaxSwapAmounts(assets, maxAmounts);

            uint assetBalanceBefore = IERC20(asset1).balanceOf(address(revenueRouter));
            vm.prank(multisig);
            revenueRouter.processAccumulatedAssets(50);
            uint assetBalanceAfterBuyBack = IERC20(asset1).balanceOf(address(revenueRouter));
            assertEq(assetBalanceBefore - assetBalanceAfterBuyBack, 1e21);
        }
    }

    function _upgradeRevenueRouter() internal {
        address[] memory proxies = new address[](1);
        proxies[0] = address(revenueRouter);
        address[] memory implementations = new address[](1);
        implementations[0] = address(new RevenueRouter());
        vm.startPrank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.11.0-alpha", proxies, implementations);
        skip(18 hours);
        IPlatform(PLATFORM).upgrade();
        revenueRouter.setBuyBackRate(100);
        vm.stopPrank();
        rewind(17 hours);
    }
}
