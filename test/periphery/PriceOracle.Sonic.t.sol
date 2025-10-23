// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {ChainlinkAdapter} from "../../src/adapters/ChainlinkAdapter.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IOracleAdapter} from "../../src/interfaces/IOracleAdapter.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IAggregatorInterfaceMinimal} from "../../src/integrations/chainlink/IAggregatorInterfaceMinimal.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {VaultOracle} from "../../src/periphery/VaultOracle.sol";

contract PriceOracleTestSonic is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant VAULT = 0xb773B791F3baDB3b28BC7A2da18E2a012b9116c2; // C-USDC.escUSD-ISF

    address public multisig;

    uint internal constant FORK_BLOCK = 4690000; // Jan-20-2025 02:26:58 PM +UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        multisig = IPlatform(PLATFORM).multisig();
    }

    function _addAdapterWithOracle() internal {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new ChainlinkAdapter()));
        ChainlinkAdapter(address(proxy)).initialize(PLATFORM);
        IPriceReader priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
        vm.prank(multisig);
        priceReader.addAdapter(address(proxy));
        IOracleAdapter adapter = IOracleAdapter(address(proxy));

        address[] memory assets = new address[](1);
        assets[0] = SonicConstantsLib.TOKEN_SCUSD;
        address[] memory feeds = new address[](1);
        feeds[0] = SonicConstantsLib.ORACLE_PYTH_SCUSD_USD;
        vm.prank(multisig);
        adapter.addPriceFeeds(assets, feeds);
    }

    // !TODO
    function testVaultOracle() internal {
        vm.expectRevert("Not trusted");
        new VaultOracle(VAULT);

        _addAdapterWithOracle();
        address vaultOracle = address(new VaultOracle(VAULT));

        int oraclePrice = IAggregatorInterfaceMinimal(vaultOracle).latestAnswer();
        assertEq(oraclePrice, 101757054);
    }
}
