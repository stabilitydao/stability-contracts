// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../base/chains/RealSetup.sol";

contract DiaAdapterTest is RealSetup {
    IOracleAdapter public adapter;

    constructor() {
        _init();
        adapter = IOracleAdapter(PriceReader(platform.priceReader()).adapters()[0]);
    }

    function testDia() public {
        (uint ethPrice,) = adapter.getPrice(RealLib.TOKEN_WREETH);
        assertGt(ethPrice, 1000e18);
        assertLt(ethPrice, 2700e18);
    }
}
