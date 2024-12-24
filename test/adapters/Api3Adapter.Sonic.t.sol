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
