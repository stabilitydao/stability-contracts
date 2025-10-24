// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

//import {console} from "forge-std/console.sol";
import {Test} from "forge-std/Test.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {ChainlinkAdapter} from "../../src/adapters/ChainlinkAdapter.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IPriceAggregator} from "../../src/interfaces/IPriceAggregator.sol";
import {IOracleAdapter} from "../../src/interfaces/IOracleAdapter.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IAggregatorInterfaceMinimal} from "../../src/integrations/chainlink/IAggregatorInterfaceMinimal.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {PriceOracle} from "../../src/periphery/PriceOracle.sol";
import {ChainlinkMinimal2V3Adapter} from "../../src/adapters/ChainlinkMinimal2V3Adapter.sol";
import {PriceReader} from "../../src/core/PriceReader.sol";
import {Platform} from "../../src/core/Platform.sol";
import {PriceAggregator} from "../../src/core/PriceAggregator.sol";

contract PriceOracleTestSonic is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public constant VAULT = 0xb773B791F3baDB3b28BC7A2da18E2a012b9116c2; // C-USDC.escUSD-ISF
    address public constant VALIDATOR_1 = address(0x101);
    address public constant VALIDATOR_2 = address(0x102);
    address public constant VALIDATOR_3 = address(0x103);

    address public multisig;

    uint public constant FORK_BLOCK = 51713531; // Oct-24-2025 03:31:29 AM +UTC

    struct Prices {
        uint priceFromPriceAggregator;
        uint priceFromAdapter;
        uint priceFromPriceReader;
        int priceFromPriceOracle;
    }

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        multisig = IPlatform(PLATFORM).multisig();

        _upgradePlatform();
    }

    function testPriceOracle() public {
        //------------------------------- Create adapter and price price aggregator
        _setUpPriceAggregator();
        IPriceAggregator priceAggregator = IPriceAggregator(IPlatform(PLATFORM).priceAggregator());
        (IOracleAdapter adapter, IAggregatorInterfaceMinimal priceOracle) =
            _addChainlinkAdapterAndOracle(SonicConstantsLib.TOKEN_STBL, priceAggregator);

        assertEq(priceOracle.decimals(), 8, "price oracle decimals 8");

        //------------------------------- Set up prices for STBL in price aggregator - round 1

        vm.prank(VALIDATOR_1);
        priceAggregator.submitPrice(SonicConstantsLib.TOKEN_STBL, 1.01e18, 1);

        vm.prank(VALIDATOR_2);
        priceAggregator.submitPrice(SonicConstantsLib.TOKEN_STBL, 1.1e18, 1);

        vm.prank(VALIDATOR_3);
        priceAggregator.submitPrice(SonicConstantsLib.TOKEN_STBL, 0.95e18, 1);

        //------------------------------- Check price on first round
        Prices memory pricesRound1 = _getPrices(priceAggregator, adapter, priceOracle);
        assertEq(pricesRound1.priceFromPriceAggregator, 1.01e18, "median price of STBL");
        assertEq(pricesRound1.priceFromAdapter, 1.01e18, "adapter price of STBL");
        assertEq(pricesRound1.priceFromPriceReader, 1.01e18, "price reader price of STBL");
        assertEq(pricesRound1.priceFromPriceOracle, int(1.01e8), "price oracle price of STBL (decimals 8)");

        //------------------------------- Set up prices for STBL in price aggregator - round 2

        vm.prank(VALIDATOR_1);
        priceAggregator.submitPrice(SonicConstantsLib.TOKEN_STBL, 2.0e18, 2);

        vm.prank(VALIDATOR_2);
        priceAggregator.submitPrice(SonicConstantsLib.TOKEN_STBL, 2.2e18, 2);

        vm.prank(VALIDATOR_3);
        priceAggregator.submitPrice(SonicConstantsLib.TOKEN_STBL, 2.1e18, 2);

        //------------------------------- Check price on first round
        Prices memory pricesRound2 = _getPrices(priceAggregator, adapter, priceOracle);
        assertEq(pricesRound2.priceFromPriceAggregator, 2.1e18, "median price of STBL 2");
        assertEq(pricesRound2.priceFromAdapter, 2.1e18, "adapter price of STBL 2");
        assertEq(pricesRound2.priceFromPriceReader, 2.1e18, "price reader price of STBL 2");
        assertEq(pricesRound2.priceFromPriceOracle, int(2.1e8), "price oracle price of STBL (decimals 8) 2");
    }

    function _getPrices(
        IPriceAggregator priceAggregator,
        IOracleAdapter adapter,
        IAggregatorInterfaceMinimal priceOracle
    ) internal view returns (Prices memory dest) {
        IPriceReader priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());

        (dest.priceFromPriceAggregator,,) = priceAggregator.price(SonicConstantsLib.TOKEN_STBL);
        (dest.priceFromAdapter,) = adapter.getPrice(SonicConstantsLib.TOKEN_STBL);
        (dest.priceFromPriceReader,) = priceReader.getPrice(SonicConstantsLib.TOKEN_STBL);
        dest.priceFromPriceOracle = priceOracle.latestAnswer();

        return dest;
    }

    //region --------------------------------- Helpers
    function _upgradePlatform() internal {
        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](2);
        proxies[0] = address(platform.priceReader());
        proxies[1] = address(platform);

        address[] memory implementations = new address[](2);
        implementations[0] = address(new PriceReader());
        implementations[1] = address(new Platform());

        vm.prank(multisig);
        IPlatform(PLATFORM).cancelUpgrade();

        vm.startPrank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.05.0-alpha", proxies, implementations);
        skip(1 days);
        IPlatform(PLATFORM).upgrade();
        vm.stopPrank();
    }

    function _setUpPriceAggregator() internal {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new PriceAggregator()));

        IPriceAggregator priceAggregator = IPriceAggregator(address(proxy));
        priceAggregator.initialize(PLATFORM);

        vm.prank(multisig);
        Platform(PLATFORM).setupPriceAggregator(address(proxy));

        vm.prank(multisig);
        priceAggregator.addValidator(VALIDATOR_1);

        vm.prank(multisig);
        priceAggregator.addValidator(VALIDATOR_2);

        vm.prank(multisig);
        priceAggregator.addValidator(VALIDATOR_3);

        vm.prank(multisig);
        priceAggregator.setMinQuorum(3);
    }

    function _addChainlinkAdapterAndOracle(
        address entity_,
        IPriceAggregator priceAggregator_
    ) internal returns (IOracleAdapter adapter, IAggregatorInterfaceMinimal priceOracle) {
        priceOracle = IAggregatorInterfaceMinimal(address(new PriceOracle(entity_, address(priceAggregator_))));

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new ChainlinkAdapter()));
        ChainlinkAdapter(address(proxy)).initialize(PLATFORM);

        IPriceReader priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());

        vm.prank(multisig);
        priceReader.addAdapter(address(proxy));

        adapter = IOracleAdapter(address(proxy));

        address[] memory assets = new address[](1);
        assets[0] = SonicConstantsLib.TOKEN_STBL;

        address[] memory feeds = new address[](1);
        feeds[0] = address(new ChainlinkMinimal2V3Adapter(address(priceOracle)));

        vm.prank(multisig);
        adapter.addPriceFeeds(assets, feeds);

        return (adapter, priceOracle);
    }
    //endregion --------------------------------- Helpers
}
