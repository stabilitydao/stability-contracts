// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PriceReader, IPriceReader, IPlatform} from "../../src/core/PriceReader.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";

/// @notice #348
contract PriceReaderUpgradeTransientCacheSonicTest is Test {
    uint public constant FORK_BLOCK = 40550698; // Jul-28-2025 05:46:21 AM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public multisig;
    IPriceReader public priceReader;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
    }

    function setUp() public {
        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
        multisig = IPlatform(PLATFORM).multisig();
        _upgradePriceReader();
    }

    /// @notice Ensure that the address can be added to whitelist and removed from it
    function testChangeWhitelistTransientCache() public {
        assertEq(priceReader.whitelistTransientCache(address(this)), false);

        vm.expectRevert(IControllable.NotOperator.selector);
        vm.prank(address(this));
        priceReader.changeWhitelistTransientCache(address(this), true);

        vm.prank(multisig);
        priceReader.changeWhitelistTransientCache(address(this), true);

        assertEq(priceReader.whitelistTransientCache(address(this)), true);

        vm.prank(multisig);
        priceReader.changeWhitelistTransientCache(address(this), false);

        assertEq(priceReader.whitelistTransientCache(address(this)), false);
    }

    /// @notice Ensure that preCalculatePriceTx can be called only by whitelisted address only
    function testPreCalculatePriceTx() public {
        vm.expectRevert(IPriceReader.NotWhitelistedTransientCache.selector);
        vm.prank(address(this));
        priceReader.preCalculatePriceTx(SonicConstantsLib.METAVAULT_META_USD);

        vm.prank(multisig);
        priceReader.changeWhitelistTransientCache(address(this), true);

        vm.prank(address(this));
        priceReader.preCalculatePriceTx(SonicConstantsLib.METAVAULT_META_USD);
    }

    /// @notice Ensure that preCalculateVaultPriceTx can be called only by whitelisted address only
    function testPreCalculateVaultPriceTx() public {
        vm.expectRevert(IPriceReader.NotWhitelistedTransientCache.selector);
        vm.prank(address(this));
        priceReader.preCalculateVaultPriceTx(SonicConstantsLib.VAULT_C_USDC_S_49);

        vm.prank(multisig);
        priceReader.changeWhitelistTransientCache(address(this), true);

        vm.prank(address(this));
        priceReader.preCalculateVaultPriceTx(SonicConstantsLib.VAULT_C_USDC_S_49);
    }

    /// @notice Ensure that getting price in cache mode less expensive than without cache
    function testPreCalculatePrices() public {
        // ------------------------------ Get prices from the price reader with enabled cache
        uint gas0 = gasleft();
        (uint priceMetaUsd,) = priceReader.getPrice(SonicConstantsLib.METAVAULT_META_USD);
        uint gasMetaUsdPriceNoCache = gas0 - gasleft();

        gas0 = gasleft();
        (uint priceVault,) = priceReader.getVaultPrice(SonicConstantsLib.VAULT_C_USDC_S_49);
        uint gasVaultPriceNoCache = gas0 - gasleft();

        // ------------------------------ Get prices from the price reader with cache
        vm.prank(multisig);
        priceReader.changeWhitelistTransientCache(address(this), true);

        priceReader.preCalculatePriceTx(SonicConstantsLib.METAVAULT_META_USD);
        priceReader.preCalculateVaultPriceTx(SonicConstantsLib.VAULT_C_USDC_S_49);

        gas0 = gasleft();
        (uint priceMetaUsd2,) = priceReader.getPrice(SonicConstantsLib.METAVAULT_META_USD);
        uint gasMetaUsdPriceNoCache2 = gas0 - gasleft();

        gas0 = gasleft();
        (uint priceVault2,) = priceReader.getVaultPrice(SonicConstantsLib.VAULT_C_USDC_S_49);
        uint gasVaultPriceNoCache2 = gas0 - gasleft();

        // ------------------------------ Check that prices are the same
        assertEq(priceMetaUsd, priceMetaUsd2);
        assertEq(priceVault, priceVault2);

        // ------------------------------ Check that gas costs are less with cache
        assertTrue(
            gasMetaUsdPriceNoCache2 < gasMetaUsdPriceNoCache,
            "Gas cost for metaUSD price with cache should be less than without cache"
        );
        assertTrue(
            gasVaultPriceNoCache2 < gasVaultPriceNoCache,
            "Gas cost for vault price with cache should be less than without cache"
        );
    }

    /// @notice Ensure that the price reader returns cached prices same as the not-cached values
    function testVaultPrices() public {
        // Price reader is able to cache up to 20 vaults
        // Let's check how it works with 21 vaults

        // ------------------------------ 21 vaults for test
        address[21] memory vaults = [
            SonicConstantsLib.VAULT_C_USDC_SIF,
            SonicConstantsLib.VAULT_C_USDC_S_8,
            SonicConstantsLib.VAULT_C_USDC_S_27,
            SonicConstantsLib.VAULT_C_USDC_S_34,
            SonicConstantsLib.VAULT_C_USDC_S_36,
            SonicConstantsLib.VAULT_C_USDC_S_49,
            SonicConstantsLib.VAULT_C_USDC_STABILITY_STREAM,
            SonicConstantsLib.VAULT_C_USDC_STABILITY_STABLEJACK,
            SonicConstantsLib.VAULT_C_USDC_SIMF_VALMORE,
            SonicConstantsLib.VAULT_C_WS_SIMF_VALMORE,
            SonicConstantsLib.VAULT_C_USDC_S_112,
            SonicConstantsLib.VAULT_C_USDC_SIMF_GREENHOUSE,
            SonicConstantsLib.VAULT_C_WMETAUSD_USDC_121,
            SonicConstantsLib.VAULT_C_SCUSD_S_46,
            SonicConstantsLib.VAULT_C_SCUSD_EULER_MEVCAPITAL,
            SonicConstantsLib.VAULT_C_SCUSD_EULER_RE7LABS,
            SonicConstantsLib.VAULT_C_WS_SIMF_VALMORE,
            SonicConstantsLib.VAULT_C_WS_SIF_54,
            SonicConstantsLib.VAULT_C_USDC_SCUSD_ISF_SCUSD,
            SonicConstantsLib.VAULT_C_USDC_SCUSD_ISF_USDC,
            SonicConstantsLib.VAULT_LEV_SIL_STS_S
        ];

        // ------------------------------ Get prices from the price reader with disabled cache
        (uint[] memory pricesNoCache, uint gasNoCache) = _getPrices(vaults);

        // ------------------------------ Get prices from the price reader with enabled cache
        vm.prank(multisig);
        priceReader.changeWhitelistTransientCache(address(this), true);

        for (uint i = 0; i < vaults.length; i++) {
            priceReader.preCalculateVaultPriceTx(vaults[i]);
        }

        (uint[] memory pricesCache, uint gasCache) = _getPrices(vaults);

        // ------------------------------ Reset the cache and ask prices once more
        priceReader.preCalculateVaultPriceTx(address(0));

        // ------------------------------ Get prices from the price reader with cache reset
        (uint[] memory pricesNoCache2, uint gasNoCache2) = _getPrices(vaults);

        // ------------------------------ Check that prices are the same
        for (uint i = 0; i < vaults.length; i++) {
            assertEq(pricesNoCache[i], pricesCache[i], "Cached and not-cached prices should be equal");
            assertEq(
                pricesNoCache[i], pricesNoCache2[i], "Not-cached prices should be equal to the prices after cache reset"
            );
        }

        // ------------------------------ Check that gas costs are less with cache
        assertLt(
            gasCache * 10,
            gasNoCache,
            "Gas cost for vault prices with cache should be less than without cache (at least 10 times)"
        );

        assertApproxEqAbs(
            gasNoCache2,
            gasNoCache,
            gasNoCache / 2,
            "Gas cost for vault prices after cache reset should be same order as the initial gas cost"
        );
    }

    //region --------------------------------- Internal logic
    function _getPrices(address[21] memory vaults) internal view returns (uint[] memory prices, uint gas) {
        uint gas0 = gasleft();
        prices = new uint[](vaults.length);
        for (uint i = 0; i < vaults.length; i++) {
            (prices[i],) = priceReader.getVaultPrice(vaults[i]);
        }
        gas = gas0 - gasleft();
    }
    //endregion --------------------------------- Internal logic

    //region --------------------------------- Helpers
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
    //endregion --------------------------------- Helpers
}
