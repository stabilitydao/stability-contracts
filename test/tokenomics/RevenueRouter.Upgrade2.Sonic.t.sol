// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {RevenueRouter, IRevenueRouter} from "../../src/tokenomics/RevenueRouter.sol";
import {IVault} from "../../src/interfaces/IVault.sol";

contract RevenueRouterUpgrade2TestSonic is Test {
    uint public constant FORK_BLOCK = 38180263; // Jul-12-2025 10:07:41 AM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public multisig;
    IRevenueRouter public revenueRouter;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        multisig = IPlatform(PLATFORM).multisig();
        revenueRouter = IRevenueRouter(IPlatform(PLATFORM).revenueRouter());
        _upgradeRevenueRouter();
    }

    function testUpgrade140() public {
        revenueRouter.processUnitsRevenue();
        vm.prank(IPlatform(PLATFORM).hardWorker());
        IVault(SonicConstantsLib.VAULT_LEV_SiL_stS_S).doHardWork();
        address[] memory vaultsAccumulated = revenueRouter.vaultsAccumulated();
        assertEq(vaultsAccumulated.length, 2);
    }

    function _upgradeRevenueRouter() internal {
        address[] memory proxies = new address[](1);
        proxies[0] = address(revenueRouter);
        address[] memory implementations = new address[](1);
        implementations[0] = address(new RevenueRouter());
        vm.startPrank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.07.2-alpha", proxies, implementations);
        skip(18 hours);
        IPlatform(PLATFORM).upgrade();
        vm.stopPrank();
        rewind(17 hours);
    }
}
