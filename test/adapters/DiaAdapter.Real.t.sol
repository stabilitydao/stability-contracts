// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/RealSetup.sol";

contract DiaAdapterTest is RealSetup {
    DiaAdapter public adapter;

    constructor() {
        _init();
        adapter = DiaAdapter(PriceReader(platform.priceReader()).adapters()[0]);
    }

    function testDia() public {
        (uint ethPrice,) = adapter.getPrice(RealLib.TOKEN_WREETH);
        assertGt(ethPrice, 1000e18);
        assertLt(ethPrice, 2700e18);

        (uint zero,) = adapter.getPrice(address(10));
        assertEq(zero, 0);

        adapter.getAllPrices();
        adapter.assets();

        // test adm methods
        address[] memory fakeAssets = new address[](2);
        fakeAssets[0] = address(0);
        fakeAssets[1] = address(1);
        vm.expectRevert(IControllable.IncorrectArrayLength.selector);
        adapter.addPriceFeeds(new address[](1), fakeAssets);

        vm.expectRevert(IControllable.AlreadyExist.selector);
        adapter.addPriceFeeds(new address[](2), fakeAssets);

        vm.expectRevert(IControllable.NotExist.selector);
        adapter.removePriceFeeds(fakeAssets);
    }
}
