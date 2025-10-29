// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console, Test, Vm} from "forge-std/Test.sol";
import {BridgedSTBL} from "../../src/tokenomics/BridgedSTBL.sol";
import {STBLOFTAdapter} from "../../src/tokenomics/STBLOFTAdapter.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {AvalancheConstantsLib} from "../../chains/avalanche/AvalancheConstantsLib.sol";
import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {MessagingReceipt, MessagingFee } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";
import {OFTMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {ExecutorConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import {InboundPacket, PacketDecoder} from "@layerzerolabs/lz-evm-protocol-v2/../oapp/contracts/precrime/libs/Packet.sol";
import { PacketV1Codec } from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";

contract BridgedSTBLTest is Test {
    using OptionsBuilder for bytes;
    using PacketV1Codec for bytes;

    address public multisigSonic;
    address public multisigAvalanche;

    uint private constant SONIC_FORK_BLOCK = 52228979; // Oct-28-2025 01:14:21 PM +UTC
    uint private constant AVALANCHE_FORK_BLOCK = 71037861; // Oct-28-2025 13:17:17 UTC

    /// @dev Set to 0 for immediate switch, or block number for gradual migration
    uint private constant GRACE_PERIOD = 0;

    uint32 private constant CONFIG_TYPE_EXECUTOR = 1;
    uint32 private constant CONFIG_TYPE_ULN = 2;

    address internal constant SONIC_DVN_SAMPLE_1 = 0xdfBb5C677dB41b5EF3a180509CDe27B5c9784655;
    address internal constant SONIC_DVN_SAMPLE_2 = 0xb2c7832aA8DDA878De6f949485f927e9e532E92C;

    address internal constant AVALANCHE_DVN_SAMPLE_1 = 0x92ef4381a03372985985E70fb15E9F081E2e8D14;
    address internal constant AVALANCHE_DVN_SAMPLE_2 = 0x7B8a0fD9D6ae5011d5cBD3E85Ed6D5510F98c9Bf;

    uint internal forkSonic;
    uint internal forkAvalanche;

    STBLOFTAdapter internal adapter;
    BridgedSTBL internal bridgedToken;

    constructor() {
        forkSonic = vm.createFork(vm.envString("SONIC_RPC_URL"), SONIC_FORK_BLOCK);
        forkAvalanche = vm.createFork(vm.envString("AVALANCHE_RPC_URL"), AVALANCHE_FORK_BLOCK);

        vm.selectFork(forkSonic);
        multisigSonic = IPlatform(SonicConstantsLib.PLATFORM).multisig();

        vm.selectFork(forkAvalanche);
        multisigAvalanche = IPlatform(AvalancheConstantsLib.PLATFORM).multisig();

        // ------------------- Create adapter and bridged token
        bridgedToken = BridgedSTBL(setupSTBLBridgedOnAvalanche());
        adapter = STBLOFTAdapter(setupSTBLOFTAdapterOnSonic());

        // ------------------- Set up layer zero
        _setupLayerZeroConfig(
            forkSonic,
            address(adapter),
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
            address(adapter),
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            SonicConstantsLib.LAYER_ZERO_V2_EXECUTOR,
            requiredDVNs,
            multisigSonic,
            SonicConstantsLib.LAYER_ZERO_V2_SEND_ULN_302
        );

        _setupLayerZeroConfig(
            forkAvalanche,
            address(bridgedToken),
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
            address(bridgedToken),
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            AvalancheConstantsLib.LAYER_ZERO_V2_EXECUTOR,
            requiredDVNs,
            multisigAvalanche,
            AvalancheConstantsLib.LAYER_ZERO_V2_SEND_ULN_302
        );

        // ------------------- set peers
        _setPeers();
    }

    function testViewSTBLOFTAdapter() public {
        vm.selectFork(forkSonic);

        assertEq(adapter.owner(), multisigSonic);
    }

    function testConfig() public {
        console.log("============= sonic endpoint config");
        _getConfig(
            forkSonic,
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            address(adapter),
            SonicConstantsLib.LAYER_ZERO_V2_SEND_ULN_302,
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            CONFIG_TYPE_EXECUTOR
        );

//        _getConfig(
//            forkSonic,
//            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT,
//            address(adapter),
//            SonicConstantsLib.LAYER_ZERO_V2_SEND_ULN_302,
//            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
//            CONFIG_TYPE_ULN
//        );

//        _getConfig(
//            forkAvalanche,
//            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT,
//            address(bridgedToken),
//            AvalancheConstantsLib.LAYER_ZERO_V2_RECEIVE_ULN_302,
//            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
//            CONFIG_TYPE_EXECUTOR
//        );

        console.log("============= avalanche endpoint config");
        _getConfig(
            forkAvalanche,
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            address(bridgedToken),
            AvalancheConstantsLib.LAYER_ZERO_V2_RECEIVE_ULN_302,
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            CONFIG_TYPE_ULN
        );

    }

    function testViewBridgedStbl() public {
        vm.selectFork(forkAvalanche);

        console.logBytes32(
            keccak256(abi.encode(uint(keccak256("erc7201:stability.BridgedSTBL")) - 1)) & ~bytes32(uint(0xff))
        );

        assertEq(bridgedToken.name(), "Stability STBL");
        assertEq(bridgedToken.symbol(), "STBLb");
        assertEq(bridgedToken.owner(), multisigAvalanche);
        assertEq(bridgedToken.decimals(), 18);
    }

    function testSendToAvalanche() public {
        // ------------------ Sonic: user sends tokens to himself on Avalanche
        vm.selectFork(forkSonic);

        address sender = address(this);
        uint sendAmount = 500e18;
        uint balance0 = 800e18;

        deal(SonicConstantsLib.TOKEN_STBL, address(this), balance0);

        IERC20(SonicConstantsLib.TOKEN_STBL).approve(address(adapter), sendAmount);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(2_000_000, 0);

        SendParam memory sendParam = SendParam({
            dstEid: AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            to: bytes32(uint256(uint160(address(this)))),
            amountLD: sendAmount,
            minAmountLD: sendAmount,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });

        assertEq(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(sender), balance0, "balance STBL before");
        assertEq(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(address(adapter)), 0, "no tokens in adapter");

        // ------------------- Prepare fee
        MessagingFee memory msgFee = adapter.quoteSend(sendParam, false);
        deal(sender, 1 ether);

        // ------------------- Send
        vm.recordLogs();
        vm.prank(sender);
        (MessagingReceipt memory msgReceipt, ) = adapter.send{value: msgFee.nativeFee}(sendParam, msgFee, sender);


        // ------------------- Extract message from emitted event
        bytes memory message;
        {
            bytes memory encodedPayload;
            bytes32 sig = keccak256("PacketSent(bytes,bytes,address)"); // PacketSent(bytes encodedPayload, bytes options, address sendLibrary)
            Vm.Log[] memory logs = vm.getRecordedLogs();
            for (uint i; i < logs.length; ++i) {
                if (logs[i].topics[0] == sig) {
                    (encodedPayload, , ) = abi.decode(logs[i].data, (bytes, bytes, address));
                    break;
                }
            }



            // repeat decoding logic from Packet.sol\decode() and PacketV1Codec.sol\message()
            { // message = bytes(encodedPayload[113:]);
                uint256 start = 113;
                require(encodedPayload.length >= start, "encodedPayload too short");
                uint256 msgLen = encodedPayload.length - start;
                message = new bytes(msgLen);
                for (uint256 i = 0; i < msgLen; ++i) {
                    message[i] = encodedPayload[start + i];
                }
            }

        }
        console.logBytes(message);

        // ------------------- Check results
        assertEq(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(sender), balance0 - sendAmount, "balance STBL after");
        assertEq(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(address(adapter)), sendAmount, "all tokens are in adapter");

        // ------------------ Avalanche: simulate message reception
        vm.selectFork(forkAvalanche);

        Origin memory origin = Origin({
            srcEid: SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            sender: bytes32(uint256(uint160(address(adapter)))),
            nonce: 1
        });

        assertEq(bridgedToken.balanceOf(sender), 0, "user has no tokens on avalanche");

        vm.prank(AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT);
        bridgedToken.lzReceive(
            origin,
            bytes32(0), // guid
            message,
            address(0), // executor
            ""          // extraData
        );

        uint balanceAfter = IERC20(bridgedToken).balanceOf(sender);
        console.log("balanceAfter:", balanceAfter);
        assertEq(balanceAfter, sendAmount, "user received tokens on Avalanche");
    }

    //region ------------------------------------- Internal logic
    function setupSTBLBridgedOnAvalanche() internal returns (address) {
        vm.selectFork(forkAvalanche);

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new BridgedSTBL(AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT)));
        BridgedSTBL bridgedStbl = BridgedSTBL(address(proxy));
        bridgedStbl.initialize(address(AvalancheConstantsLib.PLATFORM));

        assertEq(bridgedStbl.owner(), multisigAvalanche, "multisigAvalanche is owner");

        return address(bridgedStbl);
    }

    function setupSTBLOFTAdapterOnSonic() internal returns (address) {
        vm.selectFork(forkSonic);

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new STBLOFTAdapter(SonicConstantsLib.TOKEN_STBL, SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT)));
        STBLOFTAdapter stblOFTAdapter = STBLOFTAdapter(address(proxy));
        stblOFTAdapter.initialize(address(SonicConstantsLib.PLATFORM));

        assertEq(stblOFTAdapter.owner(), multisigSonic, "multisigSonic is owner");

        return address(stblOFTAdapter);
    }

    function _setupLayerZeroConfig(uint256 forkId, address oapp, uint32 dstEid, address endpoint, address sendLib, uint32 srcEid, address receiveLib, address multisig) internal {
        vm.selectFork(forkId);

        // Set send library for outbound messages
        vm.prank(multisig);
        ILayerZeroEndpointV2(endpoint).setSendLibrary(
            oapp,    // OApp address
            dstEid,  // Destination chain EID
            sendLib  // SendUln302 address
        );

        // Set receive library for inbound messages
        vm.prank(multisig);
        ILayerZeroEndpointV2(endpoint).setReceiveLibrary(
            oapp,        // OApp address
            srcEid,      // Source chain EID
            receiveLib,  // ReceiveUln302 address
            GRACE_PERIOD  // Grace period for library switch
        );
    }

    function _setPeers() internal {
        // ------------------- Sonic: set up peer connection
        vm.selectFork(forkSonic);

        vm.prank(multisigSonic);
        adapter.setPeer(
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            bytes32(uint256(uint160(address(bridgedToken))))
        );

        // ------------------- Avalanche: set up peer connection
        vm.selectFork(forkAvalanche);

        vm.prank(multisigAvalanche);
        bridgedToken.setPeer(
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            bytes32(uint256(uint160(address(adapter))))
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
        uint256 forkId,
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
            confirmations: 20,              // Minimum block confirmations
            requiredDVNCount: 2,
            optionalDVNCount: type(uint8).max,
            requiredDVNs: requiredDVNs,     // sorted list of required DVN addresses
            optionalDVNs: new address[](0),
            optionalDVNThreshold: 0
        });

        ExecutorConfig memory exec = ExecutorConfig({
            maxMessageSize: 10000,  // max bytes per cross-chain message
            executor: executor // address that pays destination execution fees
        });

        bytes memory encodedUln  = abi.encode(uln);
        bytes memory encodedExec = abi.encode(exec);

        SetConfigParam[] memory params = new SetConfigParam[](2);
        params[0] = SetConfigParam(remoteEid, CONFIG_TYPE_EXECUTOR, encodedExec);
        params[1] = SetConfigParam(remoteEid, CONFIG_TYPE_ULN, encodedUln);

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

    //endregion ------------------------------------- Internal logic
}
