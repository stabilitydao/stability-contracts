// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IRevenueRouter} from "../../src/tokenomics/RevenueRouter.sol";
import {IFeeTreasury, FeeTreasury} from "../../src/tokenomics/FeeTreasury.sol";

contract FeeTreasuryUpgradeTest is Test {
    uint public constant FORK_BLOCK = 58970278;
    address public multisig;
    IRevenueRouter public revenueRouter;
    IFeeTreasury internal feeTreasury;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        multisig = IPlatform(SonicConstantsLib.PLATFORM).multisig();
        revenueRouter = IRevenueRouter(IPlatform(SonicConstantsLib.PLATFORM).revenueRouter());
        feeTreasury = IFeeTreasury(revenueRouter.units()[0].feeTreasury);
        _upgradeFeeTreasury();
    }

    function testAddRemoveAssets() public {
        address[] memory assets = new address[](3);
        assets[0] = 0xb90a84F285aE8D3c0ceD37deD6Fc0f943f7279b7;
        assets[1] = 0x46b2E96725F03873Cb586a7f84c22545F2835F31;
        assets[2] = 0x00886bC6a12d8D5ad0ef51e041a8AB37A0E59251;

        vm.prank(SonicConstantsLib.MULTISIG);
        FeeTreasury(0x3950b3a43fa0687561Bc5c8E32D2EE826D88a661).addAssets(assets);

        assets = new address[](6);
        assets[0] = 0xdDfBF8e25Be0e36351dE8C2a811A0319Ec42E0fD;
        assets[1] = 0x7A41DF9418509725AB5637f1984F3e6d6E6C899b;
        assets[2] = 0x64d0071044EF8F98B8E5ecFCb4A6c12Cb8BC1Ec0;
        assets[3] = 0x9154f0a385eef5d48ceF78D9FEA19995A92718a9;
        assets[4] = 0x61bC5Ce0639aA0A24Ab7ea8B574D4B0D6b619833;
        assets[5] = 0x62E8eEe1aAAc7978672f90da21e4de766213b574;

        vm.prank(SonicConstantsLib.MULTISIG);
        FeeTreasury(0x3950b3a43fa0687561Bc5c8E32D2EE826D88a661).removeAssets(assets);
    }

    function _upgradeFeeTreasury() internal {
        address[] memory proxies = new address[](1);
        proxies[0] = address(feeTreasury);
        address[] memory implementations = new address[](1);
        implementations[0] = address(new FeeTreasury());
        vm.startPrank(multisig);
        IPlatform(SonicConstantsLib.PLATFORM).announcePlatformUpgrade("2025.12.2-alpha", proxies, implementations);
        skip(18 hours);
        IPlatform(SonicConstantsLib.PLATFORM).upgrade();
        vm.stopPrank();
        rewind(17 hours);
    }
}
