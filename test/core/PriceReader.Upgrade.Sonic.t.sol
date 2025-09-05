// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PriceReader, IPriceReader, IPlatform} from "../../src/core/PriceReader.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";

contract PriceReaderSonicTest is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public multisig;
    IPriceReader public priceReader;

    constructor() {
        // May-10-2025 10:38:26 AM +UTC
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), 25729900));
    }

    function setUp() public {
        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
        multisig = IPlatform(PLATFORM).multisig();
        _upgradePriceReader();
    }

    function test_PriceReader_management() public {
        address[] memory vaults = new address[](1);
        vaults[0] = SonicConstantsLib.VAULT_C_USDC_S_8;
        vm.expectRevert(IControllable.NotOperator.selector);
        priceReader.addSafeSharePrices(vaults);
        vm.prank(multisig);
        priceReader.addSafeSharePrices(vaults);
        assertEq(priceReader.vaultsWithSafeSharePrice().length, 1);
        (uint price, bool safe) = priceReader.getVaultPrice(vaults[0]);
        assertEq(safe, true);
        assertGt(price, 1e18);
        assertLt(price, 12e17);

        vm.prank(multisig);
        priceReader.removeSafeSharePrices(vaults);
        assertEq(priceReader.vaultsWithSafeSharePrice().length, 0);
    }

    function _upgradePriceReader() internal {
        address[] memory proxies = new address[](1);
        proxies[0] = address(priceReader);
        address[] memory implementations = new address[](1);
        implementations[0] = address(new PriceReader());
        vm.startPrank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.05.0-alpha", proxies, implementations);
        skip(1 days);
        IPlatform(PLATFORM).upgrade();
        vm.stopPrank();
    }
}
