// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console, Test, Vm} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IPriceAggregator} from "../../src/interfaces/IPriceAggregator.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {AvalancheConstantsLib} from "../../chains/avalanche/AvalancheConstantsLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";

contract PriceAggregatorQAppTest is Test {
    using OptionsBuilder for bytes;
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

    address internal constant SONIC_DVN_SAMPLE_1 = 0xCA764b512E2d2fD15fcA1c0a38F7cFE9153148F0;
    address internal constant SONIC_DVN_SAMPLE_2 = 0x78f607fc38e071cEB8630B7B12c358eE01C31E96;

    address internal constant AVALANCHE_DVN_SAMPLE_1 = 0x1a5Df1367F21d55B13D5E2f8778AD644BC97aC6d;
    address internal constant AVALANCHE_DVN_SAMPLE_2 = 0x0Ffe02DF012299A370D5dd69298A5826EAcaFdF8;

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

        // ------------------- Set up layer zero on both chains
        _setupLayerZeroConfig(
            forkSonic,
            address(priceAggregatorQApp),
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            SonicConstantsLib.LAYER_ZERO_V2_SEND_ULN_302,
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            SonicConstantsLib.LAYER_ZERO_V2_RECEIVE_ULN_302,
            multisigSonic
        );
        address[] memory requiredDVNs = new address[](2); // list must be sorted
        requiredDVNs[0] = SONIC_DVN_SAMPLE_2;
        requiredDVNs[1] = SONIC_DVN_SAMPLE_1;
        _setUlnAndExecutor(
            forkSonic,
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            address(priceAggregatorQApp),
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            SonicConstantsLib.LAYER_ZERO_V2_EXECUTOR,
            requiredDVNs,
            multisigSonic,
            SonicConstantsLib.LAYER_ZERO_V2_SEND_ULN_302
        );

        _setupLayerZeroConfig(
            forkAvalanche,
            address(bridgedPriceOracle),
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            AvalancheConstantsLib.LAYER_ZERO_V2_SEND_ULN_302,
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            AvalancheConstantsLib.LAYER_ZERO_V2_RECEIVE_ULN_302,
            multisigAvalanche
        );
        requiredDVNs = new address[](2); // list must be sorted
        requiredDVNs[0] = AVALANCHE_DVN_SAMPLE_2;
        requiredDVNs[1] = AVALANCHE_DVN_SAMPLE_1;
        _setUlnAndExecutor(
            forkAvalanche,
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            address(bridgedPriceOracle),
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            AvalancheConstantsLib.LAYER_ZERO_V2_EXECUTOR,
            requiredDVNs,
            multisigAvalanche,
            AvalancheConstantsLib.LAYER_ZERO_V2_SEND_ULN_302
        );

        // ------------------- set peers
        _setPeers();
    }

    //region ------------------------------------- Unit tests for PriceAggregatorQApp
    function testViewPriceAggregatorQApp() public {
        vm.selectFork(forkSonic);

        console.logBytes32(
            keccak256(abi.encode(uint(keccak256("erc7201:stability.PriceAggregatorQApp")) - 1)) & ~bytes32(uint(0xff))
        );

        assertEq(priceAggregatorQApp.entity(), SonicConstantsLib.TOKEN_STBL, "stbl");
        assertEq(priceAggregatorQApp.platform(), AvalancheConstantsLib.PLATFORM, "BridgedSTBL - platform");
        assertEq(priceAggregatorQApp.owner(), multisigSonic, "BridgedSTBL - owner");
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

    function testBridgedStblsetPeers() public {
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

    //endregion ------------------------------------- Unit tests for PriceAggregatorQApp

    //region ------------------------------------- Unit tests for BridgedPriceOracle
    function testViewBridgedPriceOracle() public {
        vm.selectFork(forkAvalanche);

        console.logBytes32(
            keccak256(abi.encode(uint(keccak256("erc7201:stability.BridgedPriceOracle")) - 1)) & ~bytes32(uint(0xff))
        );

        assertEq(bridgedPriceOracle.decimals(), 8, "decimals in aave price oracle is 8");
        assertEq(bridgedPriceOracle.platform(), AvalancheConstantsLib.PLATFORM, "BridgedSTBL - platform");
        assertEq(bridgedPriceOracle.owner(), multisigAvalanche, "BridgedSTBL - owner");
    }

    function testSetTrustedSender() public {
        vm.selectFork(forkAvalanche);

        uint[] memory endpointIds = new uint[](2);
        endpointIds[0] = SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID;
        endpointIds[1] = PlasmaConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID;

        vm.prank(address(this));
        vm.expectRevert(IControllable.NotOperator.selector);
        bridgedPriceOracle.setTrustedSender(address(this), endpointIds, true);

        assertEq(
            bridgedPriceOracle.isTrustedSender(address(this), SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID),
            false,
            "initially not trusted"
        );
        assertEq(
            bridgedPriceOracle.isTrustedSender(address(this), PlasmaConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID),
            false,
            "initially not trusted"
        );

        vm.prank(multisigAvalanche);
        bridgedPriceOracle.setTrustedSender(address(this), endpointIds, true);

        assertEq(
            bridgedPriceOracle.isTrustedSender(address(this), SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID),
            true,
            "trusted"
        );
        assertEq(
            bridgedPriceOracle.isTrustedSender(address(this), PlasmaConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID),
            true,
            "trusted"
        );

        endpointIds = new uint[](1);
        endpointIds[0] = SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID;

        vm.prank(multisigAvalanche);
        bridgedPriceOracle.setTrustedSender(address(this), endpointIds, false);

        assertEq(
            bridgedPriceOracle.isTrustedSender(address(this), SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID),
            false,
            "not trusted anymore"
        );
        assertEq(
            bridgedPriceOracle.isTrustedSender(address(this), PlasmaConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID),
            true,
            "still trusted"
        );
    }

    function testBridgedPriceOraclePeers() public {
        vm.selectFork(forkSonic);

        vm.prank(address(this));
        vm.expectRevert();
        bridgedPriceOracle.setPeer(
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, bytes32(uint(uint160(address(priceAggregatorQApp))))
        );

        vm.prank(multisigSonic);
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
        vm.selectFork(forkSonic);

        // ------------------- Prepare price inside PriceAggregator
        {
            IPriceAggregator priceAggregator = IPriceAggregator(IPlatform(SonicConstantsLib.PLATFORM).priceAggregator());

            vm.prank(multisigSonic);
            priceAggregator.addAsset(SonicConstantsLib.TOKEN_STBL, 1, 1);

            vm.prank(multisigSonic);
            priceAggregator.setMinQuorum(1);

            (,, uint roundId) = priceAggregator.price(SonicConstantsLib.TOKEN_STBL);

            vm.prank(multisigSonic);
            priceAggregator.submitPrice(SonicConstantsLib.TOKEN_STBL, 1.7e18, roundId);

            (uint price,,) = priceAggregator.price(SonicConstantsLib.TOKEN_STBL);
            assertEq(price, 1.7e18, "expected price in price aggregator");
        }

        //        // ------------------- Prepare user tokens
        //        deal(sender, 1 ether); // to pay fees
        //        deal(SonicConstantsLib.TOKEN_STBL, sender, balance0);
        //
        //        vm.prank(sender);
        //        IERC20(SonicConstantsLib.TOKEN_STBL).approve(address(adapter), sendAmount);
        //
        //        // ------------------- Prepare send options
        //        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(2_000_000, 0);
        //
        //        SendParam memory sendParam = SendParam({
        //            dstEid: AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
        //            to: bytes32(uint(uint160(receiver))),
        //            amountLD: sendAmount,
        //            minAmountLD: sendAmount,
        //            extraOptions: options,
        //            composeMsg: "",
        //            oftCmd: ""
        //        });
        //        MessagingFee memory msgFee = adapter.quoteSend(sendParam, false);
        //
        //        dest.sonicBefore = _getBalancesSonic(sender, receiver);
        //
        //        // ------------------- Send
        //        vm.recordLogs();
        //
        //        vm.prank(sender);
        //        adapter.send{value: msgFee.nativeFee}(sendParam, msgFee, sender);
        //        bytes memory message = _extractSendMessage();
        //
        //        // ------------------ Avalanche: simulate message reception
        //        vm.selectFork(forkAvalanche);
        //        dest.avalancheBefore = _getBalancesAvalanche(sender, receiver);
        //
        //        Origin memory origin = Origin({
        //            srcEid: SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
        //            sender: bytes32(uint(uint160(address(adapter)))),
        //            nonce: 1
        //        });
        //
        //        vm.prank(AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT);
        //        bridgedToken.lzReceive(
        //            origin,
        //            bytes32(0), // guid: actual value doesn't matter
        //            message,
        //            address(0), // executor
        //            "" // extraData
        //        );
        //
        //        dest.avalancheAfter = _getBalancesAvalanche(sender, receiver);
        //        vm.selectFork(forkSonic);
        //        dest.sonicAfter = _getBalancesSonic(sender, receiver);
        //
        //        dest.nativeFee = msgFee.nativeFee;
        //
        //        return dest;
    }

    //endregion ------------------------------------- Send price from Sonic to Avalanche

    //region ------------------------------------- Internal logic
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

        // Set send library for outbound messages
        vm.prank(multisig);
        ILayerZeroEndpointV2(endpoint)
            .setSendLibrary(
                oapp, // OApp address
                dstEid, // Destination chain EID
                sendLib // SendUln302 address
            );

        // Set receive library for inbound messages
        vm.prank(multisig);
        ILayerZeroEndpointV2(endpoint)
            .setReceiveLibrary(
                oapp, // OApp address
                srcEid, // Source chain EID
                receiveLib, // ReceiveUln302 address
                GRACE_PERIOD // Grace period for library switch
            );
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
    function _setUlnAndExecutor(
        uint forkId,
        address endpoint,
        address oapp,
        uint32 remoteEid,
        address executor,
        address[] memory requiredDVNs,
        address multisig,
        address sendLib
    ) internal {
        vm.selectFork(forkId);

        // ---------------------- ULN (DVN) configuration ----------------------
        UlnConfig memory uln = UlnConfig({
            confirmations: 20, // Minimum block confirmations
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
    function _extractSendMessage() internal view returns (bytes memory message) {
        bytes memory encodedPayload;
        bytes32 sig = keccak256("PacketSent(bytes,bytes,address)"); // PacketSent(bytes encodedPayload, bytes options, address sendLibrary)
        Vm.Log[] memory logs = vm.getRecordedLogs();
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
