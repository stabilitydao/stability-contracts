// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test, console} from "forge-std/Test.sol";
import {MockSetup} from "../base/MockSetup.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {FeeTreasury} from "../../src/tokenomics/FeeTreasury.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";

contract FeeTreasuryTest is Test, MockSetup {
    FeeTreasury public feeTreasury;

    function setUp() public {
        Proxy feeTreasuryProxy = new Proxy();
        feeTreasuryProxy.initProxy(address(new FeeTreasury()));
        FeeTreasury(address(feeTreasuryProxy)).initialize(address(platform), platform.multisig());
        feeTreasury = FeeTreasury(address(feeTreasuryProxy));
    }

    function test_feeTreasury110() public {
        tokenA.mint(100e18);
        tokenA.transfer(address(feeTreasury), 50e18);

        tokenB.mint(10e6);
        tokenB.transfer(address(feeTreasury), 5e6);

        address[] memory assets = new address[](2);
        assets[0] = address(tokenA);
        assets[1] = address(tokenB);

        address[] memory claimers_ = new address[](3);
        claimers_[0] = address(1);
        claimers_[1] = address(2);
        claimers_[2] = address(3);
        uint[] memory shares = new uint[](3);
        shares[0] = 60;
        shares[1] = 39;
        shares[2] = 1;

        feeTreasury.setManager(address(999));
        vm.expectRevert("denied");
        feeTreasury.setClaimers(claimers_, shares);

        vm.prank(address(999));
        feeTreasury.setClaimers(claimers_, shares);

        vm.prank(address(1000));
        vm.expectRevert(IControllable.NotOperator.selector);
        feeTreasury.addAssets(assets);

        vm.prank(address(1000));
        vm.expectRevert(IControllable.NotOperator.selector);
        feeTreasury.removeAssets(assets);

        feeTreasury.addAssets(assets);

        vm.prank(address(1));
        (address[] memory outAssets, uint[] memory amounts) = feeTreasury.harvest();
        assertEq(outAssets.length, 2);
        assertEq(outAssets[0], address(tokenA));
        assertEq(outAssets[1], address(tokenB));
        assertEq(amounts.length, 2);
        assertGt(amounts[0], 0);
        assertGt(amounts[1], 0);
        assertEq(IERC20(outAssets[0]).balanceOf(address(1)), 30e18);
        assertEq(IERC20(outAssets[0]).balanceOf(address(3)), 0);
        vm.prank(address(3));
        feeTreasury.harvest();
        assertEq(IERC20(outAssets[0]).balanceOf(address(3)), 5e17);

        (address[] memory claimers, uint[] memory _shares) = feeTreasury.claimers();
        assertEq(claimers.length, 3);
        assertEq(_shares.length, 3);
        assertEq(_shares[2], 1);

        feeTreasury.removeAssets(assets);
    }

    function test_feeTreasury() public {
        tokenA.mint(100e18);
        tokenA.transfer(address(feeTreasury), 50e18);

        address[] memory assets = new address[](2);
        assets[0] = address(tokenA);
        assets[1] = address(tokenB);

        vm.expectRevert();
        feeTreasury.distribute(assets);

        address[] memory claimers_ = new address[](2);
        claimers_[0] = address(1);
        claimers_[1] = address(2);
        uint[] memory shares = new uint[](2);
        shares[0] = 60;

        vm.prank(address(100));
        //vm.expectRevert(abi.encodeWithSelector(IControllable.NotGovernanceAndNotMultisig.selector));
        vm.expectRevert("denied");
        feeTreasury.setClaimers(claimers_, shares);

        vm.expectRevert(abi.encodeWithSelector(FeeTreasury.IncorrectSharesTotal.selector));
        feeTreasury.setClaimers(claimers_, shares);

        shares[1] = 40;
        feeTreasury.setClaimers(claimers_, shares);

        shares[0] = 30;
        shares[1] = 70;
        feeTreasury.setClaimers(claimers_, shares);

        feeTreasury.distribute(assets);

        vm.expectRevert(abi.encodeWithSelector(IControllable.IncorrectMsgSender.selector));
        feeTreasury.claim(assets);

        vm.prank(address(1));
        feeTreasury.claim(assets);
        assertEq(tokenA.balanceOf(address(1)), 50e18 * 30 / 100);

        tokenA.transfer(address(feeTreasury), 50e18);
        feeTreasury.distribute(assets);
        vm.prank(address(1));
        feeTreasury.claim(assets);
        assertEq(tokenA.balanceOf(address(1)), 100e18 * 30 / 100);

        vm.prank(address(2));
        feeTreasury.claim(assets);
        assertEq(tokenA.balanceOf(address(2)), 100e18 * 70 / 100);
    }
}
