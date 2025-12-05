// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console, Test, Vm} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IBridgedPriceOracle} from "../../src/interfaces/IBridgedPriceOracle.sol";
import {IPriceAggregator} from "../../src/interfaces/IPriceAggregator.sol";
import {IPriceAggregatorOApp} from "../../src/interfaces/IPriceAggregatorOApp.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {AvalancheConstantsLib} from "../../chains/avalanche/AvalancheConstantsLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";
// import {OFTMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {ExecutorConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
// import {InboundPacket, PacketDecoder} from "@layerzerolabs/lz-evm-protocol-v2/../oapp/contracts/precrime/libs/Packet.sol";
import {PacketV1Codec} from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {IOAppReceiver} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";
import {PriceAggregatorOApp} from "../../src/periphery/PriceAggregatorOApp.sol";
import {BridgedPriceOracle} from "../../src/periphery/BridgedPriceOracle.sol";
import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";
import {BridgeTestLib} from "../tokenomics/libs/BridgeTestLib.sol";

contract PriceAggregatorOAppTest is Test {
    using PacketV1Codec for bytes;
    using SafeERC20 for IERC20;

    uint private constant SONIC_FORK_BLOCK = 52228979; // Oct-28-2025 01:14:21 PM +UTC
    uint private constant AVALANCHE_FORK_BLOCK = 71037861; // Oct-28-2025 13:17:17 UTC
    uint private constant PLASMA_FORK_BLOCK = 5398928; // Nov-5-2025 07:38:59 UTC

    /// @dev Gas limit for executor lzReceive calls
    /// 2 mln => fee = 0.78 S
    /// 100_000 => fee = 0.36 S
    uint128 private constant GAS_LIMIT = 30_000;

    PriceAggregatorOApp internal priceAggregatorOApp;
    BridgedPriceOracle internal bridgedPriceOracleAvalanche;
    BridgedPriceOracle internal bridgedPriceOraclePlasma;

    BridgeTestLib.ChainConfig internal sonic;
    BridgeTestLib.ChainConfig internal avalanche;
    BridgeTestLib.ChainConfig internal plasma;

    address internal constant TEST_DELEGATOR = address(0x999);

    constructor() {
        {
            uint forkSonic = vm.createFork(vm.envString("SONIC_RPC_URL"), SONIC_FORK_BLOCK);
            uint forkAvalanche = vm.createFork(vm.envString("AVALANCHE_RPC_URL"), AVALANCHE_FORK_BLOCK);
            uint forkPlasma = vm.createFork(vm.envString("PLASMA_RPC_URL"), PLASMA_FORK_BLOCK);

            sonic = BridgeTestLib.createConfigSonic(vm, forkSonic, TEST_DELEGATOR);
            avalanche = BridgeTestLib.createConfigAvalanche(vm, forkAvalanche, TEST_DELEGATOR);
            plasma = BridgeTestLib.createConfigPlasma(vm, forkPlasma, TEST_DELEGATOR);
        }

        // ------------------- Create adapter and bridged token
        priceAggregatorOApp = PriceAggregatorOApp(setupPriceAggregatorOAppOnSonic(TEST_DELEGATOR));
        bridgedPriceOracleAvalanche = BridgedPriceOracle(setupBridgedPriceOracle(avalanche, TEST_DELEGATOR));
        bridgedPriceOraclePlasma = BridgedPriceOracle(setupBridgedPriceOracle(plasma, TEST_DELEGATOR));

        sonic.oapp = address(priceAggregatorOApp);
        avalanche.oapp = address(bridgedPriceOracleAvalanche);
        plasma.oapp = address(bridgedPriceOraclePlasma);

        // ------------------- Set up Sonic:Avalanche
        BridgeTestLib.setUpSonicAvalanche(vm, sonic, avalanche);

        // ------------------- Set up Sonic:Plasma
        BridgeTestLib.setUpSonicPlasma(vm, sonic, plasma);
    }

    //region ------------------------------------- Unit tests for PriceAggregatorOApp
    function testViewPriceAggregatorOApp() public {
        vm.selectFork(sonic.fork);

        console.log("erc7201:stability.PriceAggregatorOApp");
        console.logBytes32(
            keccak256(abi.encode(uint(keccak256("erc7201:stability.PriceAggregatorOApp")) - 1)) & ~bytes32(uint(0xff))
        );

        assertEq(priceAggregatorOApp.entity(), SonicConstantsLib.TOKEN_STBL, "stbl");
        assertEq(priceAggregatorOApp.platform(), SonicConstantsLib.PLATFORM, "PriceAggregatorOApp - platform");
        assertEq(priceAggregatorOApp.owner(), sonic.multisig, "PriceAggregatorOApp - owner");
    }

    function testWhitelist() public {
        vm.selectFork(sonic.fork);

        vm.prank(address(this));
        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        priceAggregatorOApp.changeWhitelist(address(this), true);

        vm.prank(sonic.multisig);
        priceAggregatorOApp.changeWhitelist(address(this), true);

        bool isWhitelisted = priceAggregatorOApp.isWhitelisted(address(this));
        assertEq(isWhitelisted, true, "is whitelisted");

        vm.prank(sonic.multisig);
        priceAggregatorOApp.changeWhitelist(address(this), false);

        isWhitelisted = priceAggregatorOApp.isWhitelisted(address(this));
        assertEq(isWhitelisted, false, "not whitelisted");
    }

    function testPriceAggregatorOAppSetPeers() public {
        vm.selectFork(sonic.fork);

        vm.prank(address(this));
        vm.expectRevert();
        priceAggregatorOApp.setPeer(avalanche.endpointId, bytes32(uint(uint160(address(bridgedPriceOracleAvalanche)))));

        vm.prank(sonic.multisig);
        priceAggregatorOApp.setPeer(avalanche.endpointId, bytes32(uint(uint160(address(bridgedPriceOracleAvalanche)))));

        assertEq(
            priceAggregatorOApp.peers(avalanche.endpointId),
            bytes32(uint(uint160(address(bridgedPriceOracleAvalanche))))
        );
    }

    function testLzReceiveUnsupported() public {
        vm.selectFork(sonic.fork);

        Origin memory origin = Origin({
            srcEid: AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            sender: bytes32(uint(uint160(address(bridgedPriceOracleAvalanche)))),
            nonce: 1
        });

        vm.prank(sonic.endpoint);
        vm.expectRevert(IPriceAggregatorOApp.UnsupportedOperation.selector);
        priceAggregatorOApp.lzReceive(
            origin,
            bytes32(0), // guid: actual value doesn't matter
            hex"00", // empty message
            address(0), // executor
            "" // extraData
        );
    }

    //endregion ------------------------------------- Unit tests for PriceAggregatorOApp

    //region ------------------------------------- Unit tests for BridgedPriceOracleAvalanche
    function testViewBridgedPriceOracle() public {
        vm.selectFork(avalanche.fork);

        //        console.log("erc7201:stability.BridgedPriceOracle");
        //        console.logBytes32(
        //            keccak256(abi.encode(uint(keccak256("erc7201:stability.BridgedPriceOracle")) - 1)) & ~bytes32(uint(0xff))
        //        );

        assertEq(bridgedPriceOracleAvalanche.decimals(), 8, "decimals in aave price oracle is 8");
        assertEq(
            bridgedPriceOracleAvalanche.platform(), AvalancheConstantsLib.PLATFORM, "bridgedPriceOracle - platform"
        );
        assertEq(bridgedPriceOracleAvalanche.owner(), avalanche.multisig, "bridgedPriceOracle - owner");
        assertEq(bridgedPriceOracleAvalanche.tokenSymbol(), "STBL", "token symbol is correct");
    }

    function testBridgedPriceOraclePeers() public {
        vm.selectFork(avalanche.fork);

        vm.prank(address(this));
        vm.expectRevert();
        bridgedPriceOracleAvalanche.setPeer(sonic.endpointId, bytes32(uint(uint160(address(priceAggregatorOApp)))));

        vm.prank(avalanche.multisig);
        bridgedPriceOracleAvalanche.setPeer(sonic.endpointId, bytes32(uint(uint160(address(priceAggregatorOApp)))));

        assertEq(
            bridgedPriceOracleAvalanche.peers(sonic.endpointId), bytes32(uint(uint160(address(priceAggregatorOApp))))
        );
    }

    function testInvalidMessageFormat() public {
        vm.selectFork(avalanche.fork);

        Origin memory origin =
            Origin({srcEid: sonic.endpointId, sender: bytes32(uint(uint160(address(priceAggregatorOApp)))), nonce: 1});

        // same code as OAppEncodingLib.packPriceUsd18
        bytes32 brokenSerializedMessage = bytes32(
            (uint(222) << 240) // (!) incorrect message format
                | (uint(uint160(1)) << 80) | (uint(uint64(2)) << 16)
        );

        vm.expectRevert(IBridgedPriceOracle.InvalidMessageFormat.selector);
        vm.prank(avalanche.endpoint);
        IOAppReceiver(avalanche.oapp)
            .lzReceive(
                origin,
                bytes32(0), // guid: actual value doesn't matter
                abi.encodePacked(brokenSerializedMessage),
                address(0), // executor
                "" // extraData
            );
    }

    //endregion ------------------------------------- Unit tests for BridgedPriceOracleAvalanche

    //region ------------------------------------- Send price from Sonic to Avalanche
    function testSendPriceToAvalanche() public {
        _testSendPriceToDest(avalanche);
    }

    function testSendPriceToPlasma() public {
        _testSendPriceToDest(plasma);
    }

    function testSendPriceToAvalancheBadPaths() public {
        vm.selectFork(sonic.fork);

        address sender = address(0x1);
        deal(sender, 2 ether); // to pay fees

        (uint priceSonic,) = _setPriceOnSonic(1.7e18);

        // ------------------- Send price to Avalanche
        vm.selectFork(sonic.fork);

        bytes memory options = OptionsBuilder.addExecutorLzReceiveOption(OptionsBuilder.newOptions(), 2_000_000, 0);
        MessagingFee memory msgFee =
            priceAggregatorOApp.quotePriceMessage(AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, options, false);

        vm.recordLogs();

        // ------------------- Not whitelisted (!)
        vm.prank(sender);
        vm.expectRevert(IPriceAggregatorOApp.NotWhitelisted.selector);
        priceAggregatorOApp.sendPriceMessage{value: msgFee.nativeFee}(
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, options, msgFee
        );

        // ------------------- Whitelisted
        vm.selectFork(sonic.fork);
        vm.prank(sonic.multisig);
        priceAggregatorOApp.changeWhitelist(sender, true);

        vm.prank(sender);
        priceAggregatorOApp.sendPriceMessage{value: msgFee.nativeFee}(
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, options, msgFee
        );
        (bytes memory message,) = BridgeTestLib._extractSendMessage(vm.getRecordedLogs());

        // ------------------ Avalanche: simulate message reception
        vm.selectFork(avalanche.fork);

        Origin memory origin =
            Origin({srcEid: sonic.endpointId, sender: bytes32(uint(uint160(address(priceAggregatorOApp)))), nonce: 1});

        vm.prank(avalanche.endpoint);
        bridgedPriceOracleAvalanche.lzReceive(
            origin,
            bytes32(0), // guid: actual value doesn't matter
            message,
            address(0), // executor
            "" // extraData
        );

        (uint priceAvalanche,) = _sendPriceFromSonicToDest(sender, avalanche);
        assertEq(priceSonic, 1.7e18, "new price set on Sonic");
        assertEq(priceAvalanche, 1.7e18, "new price set on Avalanche");
    }

    function testSendPriceNotTrustedSender() public {
        vm.selectFork(sonic.fork);

        address sender = address(0x1);
        deal(sender, 2 ether); // to pay fees

        _setPriceOnSonic(1.7e18);

        // ------------------- Send price to Avalanche
        vm.selectFork(sonic.fork);

        bytes memory options = OptionsBuilder.addExecutorLzReceiveOption(OptionsBuilder.newOptions(), 2_000_000, 0);
        MessagingFee memory msgFee =
            priceAggregatorOApp.quotePriceMessage(AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, options, false);

        vm.recordLogs();

        // ------------------- Whitelisted
        vm.selectFork(sonic.fork);
        vm.prank(sonic.multisig);
        priceAggregatorOApp.changeWhitelist(sender, true);

        vm.prank(sender);
        priceAggregatorOApp.sendPriceMessage{value: msgFee.nativeFee}(
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, options, msgFee
        );
        (bytes memory message,) = BridgeTestLib._extractSendMessage(vm.getRecordedLogs());

        // ------------------ Avalanche: simulate message reception
        vm.selectFork(avalanche.fork);

        vm.expectRevert(); // onlyPeer
        vm.prank(avalanche.endpoint);
        bridgedPriceOracleAvalanche.lzReceive(
            Origin({
                srcEid: sonic.endpointId,
                sender: bytes32(uint(uint160(address(makeAddr("not trusted sender"))))),
                nonce: 1
            }),
            bytes32(0), // guid: actual value doesn't matter
            message,
            address(0), // executor
            "" // extraData
        );
    }

    /// @notice Simulate situation with delayed (and so outdated) message delivery
    function testOutdatedPrice() public {
        uint priceBase = 1.7e18;

        // ------------------- Setup whitelist and trusted sender
        vm.selectFork(sonic.fork);

        address sender = address(0x1);
        deal(sender, 10 ether); // to pay fees

        vm.prank(sonic.multisig);
        priceAggregatorOApp.changeWhitelist(sender, true);

        vm.selectFork(plasma.fork);

        // ------------------- Check initial price on Sonic
        vm.selectFork(plasma.fork);

        // ------------------- Send basePrice to target chain
        vm.selectFork(sonic.fork);
        bytes memory message1;
        uint timestamp1;
        {
            (, timestamp1) = _setPriceOnSonic(priceBase);

            bytes memory options = OptionsBuilder.addExecutorLzReceiveOption(OptionsBuilder.newOptions(), GAS_LIMIT, 0);
            MessagingFee memory msgFee = priceAggregatorOApp.quotePriceMessage(plasma.endpointId, options, false);

            vm.recordLogs();

            vm.prank(sender);
            priceAggregatorOApp.sendPriceMessage{value: msgFee.nativeFee}(plasma.endpointId, options, msgFee);
            (message1,) = BridgeTestLib._extractSendMessage(vm.getRecordedLogs());
        }

        skip(1 minutes);

        // ------------------- Send basePrice x 2 to target chain
        bytes memory message2;
        uint timestamp2;
        {
            (, timestamp2) = _setPriceOnSonic(2 * priceBase);

            bytes memory options = OptionsBuilder.addExecutorLzReceiveOption(OptionsBuilder.newOptions(), GAS_LIMIT, 0);
            MessagingFee memory msgFee = priceAggregatorOApp.quotePriceMessage(plasma.endpointId, options, false);

            vm.recordLogs();

            vm.prank(sender);
            priceAggregatorOApp.sendPriceMessage{value: msgFee.nativeFee}(plasma.endpointId, options, msgFee);
            (message2,) = BridgeTestLib._extractSendMessage(vm.getRecordedLogs());
        }
        assertNotEq(timestamp1, timestamp2, "timestamps for two messages are different");

        // ------------------ Target chain: simulate messages reception
        vm.selectFork(plasma.fork);

        Origin memory origin =
            Origin({srcEid: sonic.endpointId, sender: bytes32(uint(uint160(address(priceAggregatorOApp)))), nonce: 1});

        // ------------------ At first receive Message 2
        {
            vm.prank(plasma.endpoint);
            IOAppReceiver(plasma.oapp)
                .lzReceive(
                    origin,
                    bytes32(0), // guid: actual value doesn't matter
                    message2,
                    address(0), // executor
                    "" // extraData
                );

            (uint currentPrice, uint currentTimestamp) = IBridgedPriceOracle(plasma.oapp).getPriceUsd18();
            assertEq(currentPrice, 2 * priceBase, "current price after message 2");
            assertEq(currentTimestamp, timestamp2, "current timestamp after message 2");
        }

        // ------------------ Then receive outdated Message 1
        {
            vm.prank(plasma.endpoint);
            IOAppReceiver(plasma.oapp)
                .lzReceive(
                    origin,
                    bytes32(0), // guid: actual value doesn't matter
                    message1,
                    address(0), // executor
                    "" // extraData
                );

            (uint currentPrice, uint currentTimestamp) = IBridgedPriceOracle(plasma.oapp).getPriceUsd18();
            assertEq(currentPrice, 2 * priceBase, "current price is not changed (it's still from message 2)");
            assertEq(currentTimestamp, timestamp2, "current timestamp wasn't changed");
        }
    }

    //endregion ------------------------------------- Send price from Sonic to Avalanche

    //region ------------------------------------- Tests implementation
    function _testSendPriceToDest(BridgeTestLib.ChainConfig memory dest) public {
        // ------------------- Setup whitelist and trusted sender
        vm.selectFork(sonic.fork);

        address sender = address(0x1);
        deal(sender, 10 ether); // to pay fees

        vm.prank(sonic.multisig);
        priceAggregatorOApp.changeWhitelist(sender, true);

        vm.selectFork(dest.fork);

        // ------------------- Check initial price on Sonic
        vm.selectFork(dest.fork);
        (uint priceBefore,) = IBridgedPriceOracle(dest.oapp).getPriceUsd18();
        assertEq(priceBefore, 0, "initial price is not set");

        // ------------------- Set price in PriceAggregator on Sonic
        (uint priceSonic, uint timestampPriceSonic) = _setPriceOnSonic(1.7e18);

        // ------------------- Send price to target chain
        (uint priceAvalanche, uint timestampAvalanche) = _sendPriceFromSonicToDest(sender, dest);

        assertEq(priceSonic, 1.7e18, "price set on Sonic");
        assertEq(priceAvalanche, 1.7e18, "price set on target chain");
        assertEq(timestampAvalanche, timestampPriceSonic, "timestamp after matches timestamp sent");

        {
            int price8 = IBridgedPriceOracle(dest.oapp).latestAnswer();
            assertEq(price8, 1.7e8, "price with 8 decimals");
        }

        // ------------------- Set TINY price in PriceAggregator on Sonic
        (priceSonic, timestampPriceSonic) = _setPriceOnSonic(1);

        // ------------------- Send new price to target chain
        (priceAvalanche, timestampAvalanche) = _sendPriceFromSonicToDest(sender, dest);

        assertEq(priceSonic, 1, "price set on Sonic");
        assertEq(priceAvalanche, 1, "price set on target chain");
        assertEq(timestampAvalanche, timestampPriceSonic, "timestamp after matches timestamp sent");

        // ------------------- Set HUGE price in PriceAggregator on Sonic
        (priceSonic, timestampPriceSonic) = _setPriceOnSonic(17e38);

        // ------------------- Send new price to target chain
        (priceAvalanche, timestampAvalanche) = _sendPriceFromSonicToDest(sender, dest);

        assertEq(priceSonic, 17e38, "price set on Sonic");
        assertEq(priceAvalanche, 17e38, "price set on target chain");
        assertEq(timestampAvalanche, timestampPriceSonic, "timestamp after matches timestamp sent");
    }

    //endregion ------------------------------------- Tests implementation

    //region ------------------------------------- Internal logic
    function _setPriceOnSonic(uint targetPrice_) internal returns (uint price, uint timestamp) {
        vm.selectFork(sonic.fork);
        IPriceAggregator priceAggregator = IPriceAggregator(IPlatform(SonicConstantsLib.PLATFORM).priceAggregator());

        vm.prank(sonic.multisig);
        priceAggregator.addAsset(SonicConstantsLib.TOKEN_STBL, 1, 1);

        vm.prank(sonic.multisig);
        priceAggregator.setMinQuorum(1);

        (,, uint roundId) = priceAggregator.price(SonicConstantsLib.TOKEN_STBL);

        address[] memory validators = priceAggregator.validators();

        vm.prank(validators[0]);
        priceAggregator.submitPrice(SonicConstantsLib.TOKEN_STBL, targetPrice_, roundId == 0 ? 1 : roundId);

        (price, timestamp,) = priceAggregator.price(SonicConstantsLib.TOKEN_STBL);
        assertEq(price, targetPrice_, "expected price in price aggregator");
    }

    function _sendPriceFromSonicToDest(
        address sender,
        BridgeTestLib.ChainConfig memory dest
    ) internal returns (uint price, uint timestamp) {
        vm.selectFork(sonic.fork);

        // ------------------- Send a message with new price to target chain
        bytes memory options = OptionsBuilder.addExecutorLzReceiveOption(OptionsBuilder.newOptions(), GAS_LIMIT, 0);

        MessagingFee memory msgFee = priceAggregatorOApp.quotePriceMessage(dest.endpointId, options, false);

        vm.recordLogs();

        vm.prank(sender);
        priceAggregatorOApp.sendPriceMessage{value: msgFee.nativeFee}(dest.endpointId, options, msgFee);
        (bytes memory message,) = BridgeTestLib._extractSendMessage(vm.getRecordedLogs());

        // ------------------ Target chain: simulate message reception
        vm.selectFork(dest.fork);

        Origin memory origin =
            Origin({srcEid: sonic.endpointId, sender: bytes32(uint(uint160(address(priceAggregatorOApp)))), nonce: 1});

        uint gas = gasleft();
        vm.prank(dest.endpoint);
        IOAppReceiver(dest.oapp)
            .lzReceive(
                origin,
                bytes32(0), // guid: actual value doesn't matter
                message,
                address(0), // executor
                "" // extraData
            );
        uint gasUsed = gas - gasleft();
        assertLt(gasUsed, GAS_LIMIT, "gas used in lzReceive"); // ~ 30 ths
        console.log("gas limit, used, fee", GAS_LIMIT, gasUsed, msgFee.nativeFee);

        (price, timestamp) = IBridgedPriceOracle(dest.oapp).getPriceUsd18();
    }

    function setupPriceAggregatorOAppOnSonic(address delegator) internal returns (address) {
        vm.selectFork(sonic.fork);

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new PriceAggregatorOApp(sonic.endpoint)));
        PriceAggregatorOApp _PriceAggregatorOApp = PriceAggregatorOApp(address(proxy));
        _PriceAggregatorOApp.initialize(sonic.platform, SonicConstantsLib.TOKEN_STBL, delegator);

        assertEq(_PriceAggregatorOApp.owner(), sonic.multisig, "multisigSonic is owner");

        return address(_PriceAggregatorOApp);
    }

    function setupBridgedPriceOracle(
        BridgeTestLib.ChainConfig memory chain,
        address delegator
    ) internal returns (address) {
        vm.selectFork(chain.fork);

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new BridgedPriceOracle(chain.endpoint)));
        BridgedPriceOracle _bridgedPriceOracle = BridgedPriceOracle(address(proxy));
        _bridgedPriceOracle.initialize(address(chain.platform), "STBL", delegator);

        assertEq(_bridgedPriceOracle.owner(), chain.multisig, "multisig is owner");

        return address(_bridgedPriceOracle);
    }

    //endregion ------------------------------------- Internal logic
}
