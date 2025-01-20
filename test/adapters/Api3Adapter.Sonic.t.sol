// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/SonicSetup.sol";

contract Api3AdapterTest is SonicSetup {
    Api3Adapter public adapter;

    constructor() {
        _init();
        adapter = Api3Adapter(PriceReader(platform.priceReader()).adapters()[0]);
    }

    function testApi3() public {
        (uint usdcPrice,) = adapter.getPrice(SonicLib.TOKEN_USDC);
        // console.log(usdcPrice);
        assertGt(usdcPrice, 9e17);
        assertLt(usdcPrice, 11e17);

        (uint zero,) = adapter.getPrice(address(10));
        assertEq(zero, 0);

        adapter.getAllPrices();
        adapter.assets();

        // test adm methods
        address[] memory priceFeeds_ = new address[](2);
        priceFeeds_[0] = address(0);
        priceFeeds_[1] = address(1);
        vm.expectRevert(IControllable.IncorrectArrayLength.selector);
        adapter.addPriceFeeds(new address[](1), priceFeeds_);

        vm.expectRevert(IControllable.AlreadyExist.selector);
        adapter.addPriceFeeds(new address[](2), priceFeeds_);

        address[] memory assets = new address[](2);
        assets[0] = address(3);
        assets[1] = address(4);

        vm.startPrank(address(10));
        vm.expectRevert(IControllable.NotOperator.selector);
        adapter.addPriceFeeds(assets, priceFeeds_);
        vm.stopPrank();

        adapter.addPriceFeeds(assets, priceFeeds_);

        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        adapter.updatePriceFeed(assets[0], address(100));

        vm.prank(platform.multisig());
        adapter.updatePriceFeed(assets[0], address(100));
        assertEq(adapter.priceFeeds(assets[0]), address(100));

        vm.prank(platform.multisig());
        vm.expectRevert(IControllable.NotExist.selector);
        adapter.updatePriceFeed(address(101), address(100));

        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        adapter.removePriceFeeds(assets);

        vm.prank(platform.multisig());
        vm.expectRevert(IControllable.NotExist.selector);
        adapter.removePriceFeeds(priceFeeds_);

        vm.prank(platform.multisig());
        adapter.removePriceFeeds(assets);
        assertEq(adapter.priceFeeds(assets[0]), address(0));
    }
}
