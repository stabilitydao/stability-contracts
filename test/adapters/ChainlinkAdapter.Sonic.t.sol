// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {ChainlinkAdapter} from "../../src/adapters/ChainlinkAdapter.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IOracleAdapter} from "../../src/interfaces/IOracleAdapter.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";

contract ChainlinkAdapterTestSonic is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    IOracleAdapter public adapter;
    IPriceReader public priceReader;
    address public multisig;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(4690000); // Jan-20-2025 02:26:58 PM +UTC
    }

    function _addAdapter() internal {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new ChainlinkAdapter()));
        ChainlinkAdapter(address(proxy)).initialize(PLATFORM);
        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
        multisig = IPlatform(PLATFORM).multisig();
        vm.prank(multisig);
        priceReader.addAdapter(address(proxy));
        adapter = IOracleAdapter(address(proxy));
    }

    function testChainlinkAdapterSonic() public {
        _addAdapter();
        address[] memory assets = new address[](1);
        assets[0] = SonicConstantsLib.TOKEN_scUSD;
        address[] memory feeds = new address[](1);
        feeds[0] = SonicConstantsLib.ORACLE_PYTH_scUSD_USD;
        vm.prank(multisig);
        adapter.addPriceFeeds(assets, feeds);
        (uint price, bool trusted) = priceReader.getPrice(SonicConstantsLib.TOKEN_scUSD);
        assertGt(price, 999e15);
        assertLt(price, 101e16);
        assertEq(trusted, true);

        vm.startPrank(multisig);
        vm.expectRevert(IControllable.NotExist.selector);
        adapter.updatePriceFeed(address(101), address(100));

        adapter.updatePriceFeed(assets[0], address(100));

        vm.expectRevert(IControllable.NotExist.selector);
        adapter.removePriceFeeds(new address[](1));

        vm.stopPrank();
    }
}
