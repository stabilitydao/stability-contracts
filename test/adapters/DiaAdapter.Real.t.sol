// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/RealSetup.sol";

//contract DiaAdapterTestDisabled is RealSetup {
//    DiaAdapter public adapter;
//
//    constructor() {
//        _init();
//        adapter = DiaAdapter(PriceReader(platform.priceReader()).adapters()[0]);
//    }
//
//    function testDia() public {
//        (uint ethPrice,) = adapter.getPrice(RealLib.TOKEN_WREETH);
//        assertGt(ethPrice, 1000e18);
//        assertLt(ethPrice, 2700e18);
//
//        (uint zero,) = adapter.getPrice(address(10));
//        assertEq(zero, 0);
//
//        adapter.getAllPrices();
//        adapter.assets();
//
//        // test adm methods
//        address[] memory fakeAssets = new address[](2);
//        fakeAssets[0] = address(0);
//        fakeAssets[1] = address(1);
//        vm.expectRevert(IControllable.IncorrectArrayLength.selector);
//        adapter.addPriceFeeds(new address[](1), fakeAssets);
//
//        vm.expectRevert(IControllable.AlreadyExist.selector);
//        adapter.addPriceFeeds(new address[](2), fakeAssets);
//
//        address[] memory assets = new address[](2);
//        assets[0] = address(3);
//        assets[1] = address(4);
//        address[] memory priceFeeds_ = new address[](2);
//        priceFeeds_[0] = address(0);
//        priceFeeds_[1] = address(1);
//
//        vm.startPrank(address(10));
//        vm.expectRevert(IControllable.NotOperator.selector);
//        adapter.addPriceFeeds(assets, priceFeeds_);
//        vm.stopPrank();
//
//        adapter.addPriceFeeds(assets, priceFeeds_);
//
//        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
//        adapter.updatePriceFeed(assets[0], address(100));
//
//        vm.prank(platform.multisig());
//        adapter.updatePriceFeed(assets[0], address(100));
//        assertEq(adapter.priceFeeds(assets[0]), address(100));
//
//        vm.prank(platform.multisig());
//        vm.expectRevert(IControllable.NotExist.selector);
//        adapter.updatePriceFeed(address(101), address(100));
//
//        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
//        adapter.removePriceFeeds(assets);
//
//        vm.prank(platform.multisig());
//        vm.expectRevert(IControllable.NotExist.selector);
//        adapter.removePriceFeeds(priceFeeds_);
//
//        vm.prank(platform.multisig());
//        adapter.removePriceFeeds(assets);
//        assertEq(adapter.priceFeeds(assets[0]), address(0));
//    }
//}
