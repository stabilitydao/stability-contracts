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
        FeeTreasury(address(feeTreasuryProxy)).initialize(address(platform));
        feeTreasury = FeeTreasury(address(feeTreasuryProxy));
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
        vm.expectRevert(abi.encodeWithSelector(IControllable.NotGovernanceAndNotMultisig.selector));
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
