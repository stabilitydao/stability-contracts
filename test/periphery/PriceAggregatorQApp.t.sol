// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console, Test, Vm} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IPriceAggregator} from "../../src/interfaces/IPriceAggregator.sol";
import {IPriceAggregatorQApp} from "../../src/interfaces/IPriceAggregatorQApp.sol";
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
import {PriceAggregatorQApp} from "../../src/periphery/PriceAggregatorOApp.sol";
import {BridgedPriceOracle} from "../../src/periphery/BridgedPriceOracle.sol";

contract PriceAggregatorQAppTest is Test {
    using PacketV1Codec for bytes;
    using SafeERC20 for IERC20;

    address public multisigSonic;
    address public multisigAvalanche;

    uint private constant SONIC_FORK_BLOCK = 52228979; // Oct-28-2025 01:14:21 PM +UTC
    uint private constant AVALANCHE_FORK_BLOCK = 71037861; // Oct-28-2025 13:17:17 UTC

    /// @dev Set to 0 for immediate switch, or block number for gradual migration
    uint private constant GRACE_PERIOD = 0;

    uint32 private constant CONFIG_TYPE_EXECUTOR = 1;
    uint32 private constant CONFIG_TYPE_ULN = 2;

    /// @dev Gas limit for executor lzReceive calls
    /// 2 mln => fee = 0.78 S
    /// 100_000 => fee = 0.36 S
    uint128 private constant GAS_LIMIT = 100_000;

    // --------------- DVN config: List of DVN providers must be equal on both chains (!)

    // https://docs.layerzero.network/v2/deployments/chains/sonic
    address internal constant SONIC_DVN_SAMPLE_1 = 0x78f607fc38e071cEB8630B7B12c358eE01C31E96;
    address internal constant SONIC_DVN_SAMPLE_2 = 0xCA764b512E2d2fD15fcA1c0a38F7cFE9153148F0;

    // https://docs.layerzero.network/v2/deployments/chains/avalanche
    address internal constant AVALANCHE_DVN_SAMPLE_1 = 0x0Ffe02DF012299A370D5dd69298A5826EAcaFdF8;
    address internal constant AVALANCHE_DVN_SAMPLE_2 = 0x1a5Df1367F21d55B13D5E2f8778AD644BC97aC6d;

    // --------------- Confirmations: send >= receive, see https://docs.layerzero.network/v2/developers/evm/configuration/dvn-executor-config
    /// @dev Minimum block confirmations to wait on Sonic
    uint64 internal constant MIN_BLOCK_CONFIRMATIONS_SEND_SONIC = 15;

    /// @dev Minimum block confirmations required on Avalanche
    uint64 internal constant MIN_BLOCK_CONFIRMATIONS_RECEIVE_AVALANCHE = 10;

    uint internal forkSonic;
    uint internal forkAvalanche;

    PriceAggregatorQApp internal priceAggregatorQApp;
    BridgedPriceOracle internal bridgedPriceOracle;

    constructor() {
        forkSonic = vm.createFork(vm.envString("SONIC_RPC_URL"), SONIC_FORK_BLOCK);
        forkAvalanche = vm.createFork(vm.envString("AVALANCHE_RPC_URL"), AVALANCHE_FORK_BLOCK);

        vm.selectFork(forkSonic);
        multisigSonic = IPlatform(SonicConstantsLib.PLATFORM).multisig();

        vm.selectFork(forkAvalanche);
        multisigAvalanche = IPlatform(AvalancheConstantsLib.PLATFORM).multisig();

        // ------------------- Create adapter and bridged token
        bridgedPriceOracle = BridgedPriceOracle(setupBridgedPriceOracleOnAvalanche());
        priceAggregatorQApp = PriceAggregatorQApp(setupPriceAggregatorQAppOnSonic());

        // ------------------- Set up sending chain - Sonic
        _setupLayerZeroConfig(
            forkSonic,
            address(priceAggregatorQApp),
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            SonicConstantsLib.LAYER_ZERO_V2_SEND_ULN_302,
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            address(0), // we have one directional bridge: sonic -> avalanche, receive lib is not needed
            multisigSonic
        );
        address[] memory requiredDVNs = new address[](2); // list must be sorted
        requiredDVNs[0] = SONIC_DVN_SAMPLE_1;
        requiredDVNs[1] = SONIC_DVN_SAMPLE_2;
        _setSendConfig(
            forkSonic,
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            address(priceAggregatorQApp),
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            SonicConstantsLib.LAYER_ZERO_V2_EXECUTOR,
            requiredDVNs,
            multisigSonic,
            SonicConstantsLib.LAYER_ZERO_V2_SEND_ULN_302,
            MIN_BLOCK_CONFIRMATIONS_SEND_SONIC
        );

        // ------------------- Set up receiving chain - Avalanche
        _setupLayerZeroConfig(
            forkAvalanche,
            address(bridgedPriceOracle),
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            address(0), // we have one directional bridge: sonic -> avalanche, send lib is not needed
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            AvalancheConstantsLib.LAYER_ZERO_V2_RECEIVE_ULN_302,
            multisigAvalanche
        );
        requiredDVNs = new address[](2); // list must be sorted
        requiredDVNs[0] = AVALANCHE_DVN_SAMPLE_1;
        requiredDVNs[1] = AVALANCHE_DVN_SAMPLE_2;
        _setReceiveConfig(
            forkAvalanche,
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            address(bridgedPriceOracle),
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            requiredDVNs,
            multisigAvalanche,
            AvalancheConstantsLib.LAYER_ZERO_V2_RECEIVE_ULN_302,
            MIN_BLOCK_CONFIRMATIONS_RECEIVE_AVALANCHE
        );

        // ------------------- set peers
        _setPeers();
    }

    //region ------------------------------------- Unit tests for PriceAggregatorQApp
    function testViewPriceAggregatorQApp() public {
        vm.selectFork(forkSonic);

        //        console.log("erc7201:stability.PriceAggregatorQApp");
        //        console.logBytes32(
        //            keccak256(abi.encode(uint(keccak256("erc7201:stability.PriceAggregatorQApp")) - 1)) & ~bytes32(uint(0xff))
        //        );

        assertEq(priceAggregatorQApp.entity(), SonicConstantsLib.TOKEN_STBL, "stbl");
        assertEq(priceAggregatorQApp.platform(), SonicConstantsLib.PLATFORM, "priceAggregatorQApp - platform");
        assertEq(priceAggregatorQApp.owner(), multisigSonic, "priceAggregatorQApp - owner");
    }

    function testWhitelist() public {
        vm.selectFork(forkSonic);

        vm.prank(address(this));
        vm.expectRevert(IControllable.NotOperator.selector);
        priceAggregatorQApp.changeWhitelist(address(this), true);

        vm.prank(multisigSonic);
        priceAggregatorQApp.changeWhitelist(address(this), true);

        bool isWhitelisted = priceAggregatorQApp.isWhitelisted(address(this));
        assertEq(isWhitelisted, true, "is whitelisted");

        vm.prank(multisigSonic);
        priceAggregatorQApp.changeWhitelist(address(this), false);

        isWhitelisted = priceAggregatorQApp.isWhitelisted(address(this));
        assertEq(isWhitelisted, false, "not whitelisted");
    }

    function testPriceAggregatorQAppSetPeers() public {
        vm.selectFork(forkSonic);

        vm.prank(address(this));
        vm.expectRevert();
        priceAggregatorQApp.setPeer(
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, bytes32(uint(uint160(address(bridgedPriceOracle))))
        );

        vm.prank(multisigSonic);
        priceAggregatorQApp.setPeer(
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, bytes32(uint(uint160(address(bridgedPriceOracle))))
        );

        assertEq(
            priceAggregatorQApp.peers(AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID),
            bytes32(uint(uint160(address(bridgedPriceOracle))))
        );
    }

    function testLzReceiveUnsuppoted() public {
        vm.selectFork(forkSonic);

        Origin memory origin = Origin({
            srcEid: AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            sender: bytes32(uint(uint160(address(bridgedPriceOracle)))),
            nonce: 1
        });

        vm.prank(SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT);
        vm.expectRevert(IPriceAggregatorQApp.UnsupportedOperation.selector);
        priceAggregatorQApp.lzReceive(
            origin,
            bytes32(0), // guid: actual value doesn't matter
            hex"00", // empty message
            address(0), // executor
            "" // extraData
        );
    }

    //endregion ------------------------------------- Unit tests for PriceAggregatorQApp

    //region ------------------------------------- Unit tests for BridgedPriceOracle
    function testViewBridgedPriceOracle() public {
        vm.selectFork(forkAvalanche);

        //        console.log("erc7201:stability.BridgedPriceOracle");
        //        console.logBytes32(
        //            keccak256(abi.encode(uint(keccak256("erc7201:stability.BridgedPriceOracle")) - 1)) & ~bytes32(uint(0xff))
        //        );

        assertEq(bridgedPriceOracle.decimals(), 8, "decimals in aave price oracle is 8");
        assertEq(bridgedPriceOracle.platform(), AvalancheConstantsLib.PLATFORM, "bridgedPriceOracle - platform");
        assertEq(bridgedPriceOracle.owner(), multisigAvalanche, "bridgedPriceOracle - owner");
    }

    function testBridgedPriceOraclePeers() public {
        vm.selectFork(forkAvalanche);

        vm.prank(address(this));
        vm.expectRevert();
        bridgedPriceOracle.setPeer(
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, bytes32(uint(uint160(address(priceAggregatorQApp))))
        );

        vm.prank(multisigAvalanche);
        bridgedPriceOracle.setPeer(
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, bytes32(uint(uint160(address(priceAggregatorQApp))))
        );

        assertEq(
            bridgedPriceOracle.peers(SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID),
            bytes32(uint(uint160(address(priceAggregatorQApp))))
        );
    }

    //endregion ------------------------------------- Unit tests for BridgedPriceOracle

    //region ------------------------------------- Send price from Sonic to Avalanche
    function testSendPrice() public {
        // ------------------- Setup whitelist and trusted sender
        vm.selectFork(forkSonic);

        address sender = address(0x1);
        deal(sender, 10 ether); // to pay fees

        vm.prank(multisigSonic);
        priceAggregatorQApp.changeWhitelist(sender, true);

        vm.selectFork(forkAvalanche);

        // ------------------- Check initial price on Sonic
        vm.selectFork(forkAvalanche);
        (uint priceBefore,) = bridgedPriceOracle.getPriceUsd18();
        assertEq(priceBefore, 0, "initial price is not set");

        // ------------------- Set price in PriceAggregator on Sonic
        (uint priceSonic, uint timestampPriceSonic) = _setPriceOnSonic(1.7e18);

        // ------------------- Send price to Avalanche
        (uint priceAvalanche, uint timestampAvalanche) = _sendPriceToAvalanche(sender);

        assertEq(priceSonic, 1.7e18, "price set on Sonic");
        assertEq(priceAvalanche, 1.7e18, "price set on Avalanche");
        assertEq(timestampAvalanche, timestampPriceSonic, "timestamp after matches timestamp sent");

        {
            int price8 = bridgedPriceOracle.latestAnswer();
            assertEq(price8, 1.7e8, "price with 8 decimals");
        }

        // ------------------- Set TINY price in PriceAggregator on Sonic
        (priceSonic, timestampPriceSonic) = _setPriceOnSonic(1);

        // ------------------- Send new price to Avalanche
        (priceAvalanche, timestampAvalanche) = _sendPriceToAvalanche(sender);

        assertEq(priceSonic, 1, "price set on Sonic");
        assertEq(priceAvalanche, 1, "price set on Avalanche");
        assertEq(timestampAvalanche, timestampPriceSonic, "timestamp after matches timestamp sent");

        // ------------------- Set HUGE price in PriceAggregator on Sonic
        (priceSonic, timestampPriceSonic) = _setPriceOnSonic(17e38);

        // ------------------- Send new price to Avalanche
        (priceAvalanche, timestampAvalanche) = _sendPriceToAvalanche(sender);

        assertEq(priceSonic, 17e38, "price set on Sonic");
        assertEq(priceAvalanche, 17e38, "price set on Avalanche");
        assertEq(timestampAvalanche, timestampPriceSonic, "timestamp after matches timestamp sent");
    }

    function testSendPriceBadPaths() public {
        vm.selectFork(forkSonic);

        address sender = address(0x1);
        deal(sender, 2 ether); // to pay fees

        (uint priceSonic,) = _setPriceOnSonic(1.7e18);

        // ------------------- Send price to Avalanche
        vm.selectFork(forkSonic);

        bytes memory options = OptionsBuilder.addExecutorLzReceiveOption(OptionsBuilder.newOptions(), 2_000_000, 0);
        MessagingFee memory msgFee =
            priceAggregatorQApp.quotePriceMessage(AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, options, false);

        vm.recordLogs();

        // ------------------- Not whitelisted (!)
        vm.prank(sender);
        vm.expectRevert(IPriceAggregatorQApp.NotWhitelisted.selector);
        priceAggregatorQApp.sendPriceMessage{value: msgFee.nativeFee}(
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, options, msgFee
        );

        // ------------------- Whitelisted
        vm.selectFork(forkSonic);
        vm.prank(multisigSonic);
        priceAggregatorQApp.changeWhitelist(sender, true);

        vm.prank(sender);
        priceAggregatorQApp.sendPriceMessage{value: msgFee.nativeFee}(
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, options, msgFee
        );
        bytes memory message = _extractPayload(vm.getRecordedLogs());

        // ------------------ Avalanche: simulate message reception
        vm.selectFork(forkAvalanche);

        Origin memory origin = Origin({
            srcEid: SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            sender: bytes32(uint(uint160(address(priceAggregatorQApp)))),
            nonce: 1
        });

        vm.prank(AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT);
        bridgedPriceOracle.lzReceive(
            origin,
            bytes32(0), // guid: actual value doesn't matter
            message,
            address(0), // executor
            "" // extraData
        );

        (uint priceAvalanche,) = _sendPriceToAvalanche(sender);
        assertEq(priceSonic, 1.7e18, "new price set on Sonic");
        assertEq(priceAvalanche, 1.7e18, "new price set on Avalanche");
    }

    //endregion ------------------------------------- Send price from Sonic to Avalanche

    //region ------------------------------------- Internal logic
    function _setPriceOnSonic(uint targetPrice_) internal returns (uint price, uint timestamp) {
        vm.selectFork(forkSonic);
        IPriceAggregator priceAggregator = IPriceAggregator(IPlatform(SonicConstantsLib.PLATFORM).priceAggregator());

        vm.prank(multisigSonic);
        priceAggregator.addAsset(SonicConstantsLib.TOKEN_STBL, 1, 1);

        vm.prank(multisigSonic);
        priceAggregator.setMinQuorum(1);

        (,, uint roundId) = priceAggregator.price(SonicConstantsLib.TOKEN_STBL);

        address[] memory validators = priceAggregator.validators();

        vm.prank(validators[0]);
        priceAggregator.submitPrice(SonicConstantsLib.TOKEN_STBL, targetPrice_, roundId == 0 ? 1 : roundId);

        (price, timestamp,) = priceAggregator.price(SonicConstantsLib.TOKEN_STBL);
        assertEq(price, targetPrice_, "expected price in price aggregator");
    }

    function _sendPriceToAvalanche(address sender) internal returns (uint price, uint timestamp) {
        vm.selectFork(forkSonic);

        // ------------------- Send a message with new price to Avalanche
        bytes memory options = OptionsBuilder.addExecutorLzReceiveOption(OptionsBuilder.newOptions(), GAS_LIMIT, 0);

        MessagingFee memory msgFee =
            priceAggregatorQApp.quotePriceMessage(AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, options, false);

        vm.recordLogs();

        vm.prank(sender);
        priceAggregatorQApp.sendPriceMessage{value: msgFee.nativeFee}(
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, options, msgFee
        );
        bytes memory message = _extractPayload(vm.getRecordedLogs());

        // ------------------ Avalanche: simulate message reception
        vm.selectFork(forkAvalanche);

        Origin memory origin = Origin({
            srcEid: SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            sender: bytes32(uint(uint160(address(priceAggregatorQApp)))),
            nonce: 1
        });

        vm.prank(AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT);
        bridgedPriceOracle.lzReceive(
            origin,
            bytes32(0), // guid: actual value doesn't matter
            message,
            address(0), // executor
            "" // extraData
        );

        (price, timestamp) = bridgedPriceOracle.getPriceUsd18();
    }

    function setupPriceAggregatorQAppOnSonic() internal returns (address) {
        vm.selectFork(forkSonic);

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new PriceAggregatorQApp(SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT)));
        PriceAggregatorQApp _priceAggregatorQApp = PriceAggregatorQApp(address(proxy));
        _priceAggregatorQApp.initialize(SonicConstantsLib.PLATFORM, SonicConstantsLib.TOKEN_STBL);

        assertEq(_priceAggregatorQApp.owner(), multisigSonic, "multisigSonic is owner");

        return address(_priceAggregatorQApp);
    }

    function setupBridgedPriceOracleOnAvalanche() internal returns (address) {
        vm.selectFork(forkAvalanche);

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new BridgedPriceOracle(AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT)));
        BridgedPriceOracle _bridgedPriceOracle = BridgedPriceOracle(address(proxy));
        _bridgedPriceOracle.initialize(address(AvalancheConstantsLib.PLATFORM));

        assertEq(_bridgedPriceOracle.owner(), multisigAvalanche, "multisigAvalanche is owner");

        return address(_bridgedPriceOracle);
    }

    function _setupLayerZeroConfig(
        uint forkId,
        address oapp,
        uint32 dstEid,
        address endpoint,
        address sendLib,
        uint32 srcEid,
        address receiveLib,
        address multisig
    ) internal {
        vm.selectFork(forkId);

        if (sendLib != address(0)) {
            // Set send library for outbound messages
            vm.prank(multisig);
            ILayerZeroEndpointV2(endpoint)
                .setSendLibrary(
                    oapp, // OApp address
                    dstEid, // Destination chain EID
                    sendLib // SendUln302 address
                );
        }

        // Set receive library for inbound messages
        if (receiveLib != address(0)) {
            vm.prank(multisig);
            ILayerZeroEndpointV2(endpoint)
                .setReceiveLibrary(
                    oapp, // OApp address
                    srcEid, // Source chain EID
                    receiveLib, // ReceiveUln302 address
                    GRACE_PERIOD // Grace period for library switch
                );
        }
    }

    function _setPeers() internal {
        // ------------------- Sonic: set up peer connection
        vm.selectFork(forkSonic);

        vm.prank(multisigSonic);
        priceAggregatorQApp.setPeer(
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, bytes32(uint(uint160(address(bridgedPriceOracle))))
        );

        // ------------------- Avalanche: set up peer connection
        vm.selectFork(forkAvalanche);

        vm.prank(multisigAvalanche);
        bridgedPriceOracle.setPeer(
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, bytes32(uint(uint160(address(priceAggregatorQApp))))
        );
    }

    /// @notice Configures both ULN (DVN validators) and Executor for an OApp
    /// @param forkId        Foundry fork ID to select the target chain
    /// @param endpoint      LayerZero V2 endpoint address for this network
    /// @param oapp          Address of the OApp (adapter or bridged token)
    /// @param remoteEid     Endpoint ID (EID) of the remote chain
    /// @param executor      Address of the LayerZero Executor contract
    /// @param requiredDVNs  Array of DVN validator addresses
    /// @param confirmations  Minimum block confirmations
    function _setSendConfig(
        uint forkId,
        address endpoint,
        address oapp,
        uint32 remoteEid,
        address executor,
        address[] memory requiredDVNs,
        address multisig,
        address sendLib,
        uint64 confirmations
    ) internal {
        vm.selectFork(forkId);

        // ---------------------- ULN (DVN) configuration ----------------------
        UlnConfig memory uln = UlnConfig({
            confirmations: confirmations,
            requiredDVNCount: 2,
            optionalDVNCount: type(uint8).max,
            requiredDVNs: requiredDVNs, // sorted list of required DVN addresses
            optionalDVNs: new address[](0),
            optionalDVNThreshold: 0
        });

        ExecutorConfig memory exec = ExecutorConfig({
            maxMessageSize: 10000, // max bytes per cross-chain message
            executor: executor // address that pays destination execution fees
        });

        bytes memory encodedUln = abi.encode(uln);
        bytes memory encodedExec = abi.encode(exec);

        SetConfigParam[] memory params = new SetConfigParam[](2);
        params[0] = SetConfigParam({eid: remoteEid, configType: CONFIG_TYPE_EXECUTOR, config: encodedExec});
        params[1] = SetConfigParam({eid: remoteEid, configType: CONFIG_TYPE_ULN, config: encodedUln});

        vm.prank(multisig);
        ILayerZeroEndpointV2(endpoint).setConfig(oapp, sendLib, params);
    }

    /// @notice Configures ULN (DVN validators) for on receiving chain
    /// @dev https://docs.layerzero.network/v2/developers/evm/configuration/dvn-executor-config
    /// @param forkId        Foundry fork ID to select the target chain
    /// @param endpoint      LayerZero V2 endpoint address for this network
    /// @param oapp          Address of the OApp (adapter or bridged token)
    /// @param remoteEid     Endpoint ID (EID) of the remote chain
    /// @param requiredDVNs  Array of DVN validator addresses
    /// @param confirmations Minimum block confirmations for ULN
    /// @param multisig      Address of the multisig wallet to authorize the config change
    /// @param receiveLib       Address of the ReceiveUln302 library
    function _setReceiveConfig(
        uint forkId,
        address endpoint,
        address oapp,
        uint32 remoteEid,
        address[] memory requiredDVNs,
        address multisig,
        address receiveLib,
        uint64 confirmations
    ) internal {
        vm.selectFork(forkId);

        // ---------------------- ULN (DVN) configuration ----------------------
        UlnConfig memory uln = UlnConfig({
            confirmations: confirmations, // Minimum block confirmations
            requiredDVNCount: 2,
            optionalDVNCount: type(uint8).max,
            requiredDVNs: requiredDVNs, // sorted list of required DVN addresses
            optionalDVNs: new address[](0),
            optionalDVNThreshold: 0
        });

        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam({eid: remoteEid, configType: CONFIG_TYPE_ULN, config: abi.encode(uln)});

        vm.prank(multisig);
        ILayerZeroEndpointV2(endpoint).setConfig(oapp, receiveLib, params);
    }

    /// @notice Calls getConfig on the specified LayerZero Endpoint.
    /// @dev Decodes the returned bytes as a UlnConfig. Logs some of its fields.
    /// @dev https://docs.layerzero.network/v2/developers/evm/configuration/dvn-executor-config
    /// @param endpoint_ The LayerZero Endpoint address.
    /// @param oapp_ The address of your OApp.
    /// @param lib_ The address of the Message Library (send or receive).
    /// @param eid_ The remote endpoint identifier.
    /// @param configType_ The configuration type (1 = Executor, 2 = ULN).
    function _getConfig(
        uint forkId,
        address endpoint_,
        address oapp_,
        address lib_,
        uint32 eid_,
        uint32 configType_
    ) internal {
        // Create a fork from the specified RPC URL.
        vm.selectFork(forkId);
        vm.startBroadcast();

        // Instantiate the LayerZero endpoint.
        ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(endpoint_);
        // Retrieve the raw configuration bytes.
        bytes memory config = endpoint.getConfig(oapp_, lib_, eid_, configType_);

        if (configType_ == 1) {
            // Decode the Executor config (configType = 1)
            ExecutorConfig memory execConfig = abi.decode(config, (ExecutorConfig));
            // Log some key configuration parameters.
            console.log("Executor Type:", execConfig.maxMessageSize);
            console.log("Executor Address:", execConfig.executor);
        }

        if (configType_ == 2) {
            // Decode the ULN config (configType = 2)
            UlnConfig memory decodedConfig = abi.decode(config, (UlnConfig));
            // Log some key configuration parameters.
            console.log("Confirmations:", decodedConfig.confirmations);
            console.log("Required DVN Count:", decodedConfig.requiredDVNCount);
            for (uint i = 0; i < decodedConfig.requiredDVNs.length; i++) {
                console.logAddress(decodedConfig.requiredDVNs[i]);
            }
            console.log("Optional DVN Count:", decodedConfig.optionalDVNCount);
            for (uint i = 0; i < decodedConfig.optionalDVNs.length; i++) {
                console.logAddress(decodedConfig.optionalDVNs[i]);
            }
            console.log("Optional DVN Threshold:", decodedConfig.optionalDVNThreshold);
        }
        vm.stopBroadcast();
    }

    /// @notice Extract PacketSent message from emitted event
    function _extractPayload(Vm.Log[] memory logs) internal pure returns (bytes memory message) {
        bytes memory encodedPayload;
        bytes32 sig = keccak256("PacketSent(bytes,bytes,address)"); // PacketSent(bytes encodedPayload, bytes options, address sendLibrary)

        for (uint i; i < logs.length; ++i) {
            if (logs[i].topics[0] == sig) {
                (encodedPayload,,) = abi.decode(logs[i].data, (bytes, bytes, address));
                break;
            }
        }

        // repeat decoding logic from Packet.sol\decode() and PacketV1Codec.sol\message()
        { // message = bytes(encodedPayload[113:]);
            uint start = 113;
            require(encodedPayload.length >= start, "encodedPayload too short");
            uint msgLen = encodedPayload.length - start;
            message = new bytes(msgLen);
            for (uint i = 0; i < msgLen; ++i) {
                message[i] = encodedPayload[start + i];
            }
        }

        //        console.logBytes(message);
        return message;
    }
    //endregion ------------------------------------- Internal logic
}
