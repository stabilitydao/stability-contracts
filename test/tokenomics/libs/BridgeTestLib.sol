// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console, Vm} from "forge-std/Test.sol";
import {BridgedToken} from "../../../src/tokenomics/BridgedToken.sol";
import {StabilityOFTAdapter} from "../../../src/tokenomics/StabilityOFTAdapter.sol";
import {IPlatform} from "../../../src/interfaces/IPlatform.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {SonicConstantsLib} from "../../../chains/sonic/SonicConstantsLib.sol";
import {Proxy} from "../../../src/core/proxy/Proxy.sol";
import {AvalancheConstantsLib} from "../../../chains/avalanche/AvalancheConstantsLib.sol";
// import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import {OFTMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {ExecutorConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
// import {InboundPacket, PacketDecoder} from "@layerzerolabs/lz-evm-protocol-v2/../oapp/contracts/precrime/libs/Packet.sol";
// import {PacketV1Codec} from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import {PlasmaConstantsLib} from "../../../chains/plasma/PlasmaConstantsLib.sol";

/// @notice Auxiliary data types and utils to test STBL-bridge related functionality
library BridgeTestLib {
    /// @dev Set to 0 for immediate switch, or block number for gradual migration
    uint private constant GRACE_PERIOD = 0;
    uint32 internal constant CONFIG_TYPE_EXECUTOR = 1;
    uint32 internal constant CONFIG_TYPE_ULN = 2;

    // --------------- DVN config: List of DVN providers must be equal on both source and target chains

    // https://docs.layerzero.network/v2/deployments/chains/sonic
    address internal constant SONIC_DVN_NETHERMIND_PULL = 0x3b0531eB02Ab4aD72e7a531180beeF9493a00dD2; // Nethermind (lzRead)
    address internal constant SONIC_DVN_LAYER_ZERO_PULL = 0x78f607fc38e071cEB8630B7B12c358eE01C31E96; // LayerZero Labs (lzRead)
    address internal constant SONIC_DVN_LAYER_ZERO_PUSH = 0x282b3386571f7f794450d5789911a9804FA346b4;
    address internal constant SONIC_DVN_HORIZEN_PULL = 0xCA764b512E2d2fD15fcA1c0a38F7cFE9153148F0; // Horizen (lzRead)

    // https://docs.layerzero.network/v2/deployments/chains/avalanche
    address internal constant AVALANCHE_DVN_LAYER_ZERO_PULL = 0x0Ffe02DF012299A370D5dd69298A5826EAcaFdF8; // LayerZero Labs (lzRead)
    address internal constant AVALANCHE_DVN_LAYER_ZERO_PUSH = 0x962F502A63F5FBeB44DC9ab932122648E8352959;
    address internal constant AVALANCHE_DVN_NETHERMIND_PULL = 0x1308151a7ebaC14f435d3Ad5fF95c34160D539A5; // Nethermind (lzRead)
    address internal constant AVALANCHE_DVN_HORIZON_PULL = 0x1a5Df1367F21d55B13D5E2f8778AD644BC97aC6d; // Horizen (lzRead)

    // https://docs.layerzero.network/v2/deployments/chains/plasma
    address internal constant PLASMA_DVN_LAYER_ZERO_PUSH = 0x282b3386571f7f794450d5789911a9804FA346b4; // LayerZero Labs (push based)
    address internal constant PLASMA_DVN_NETHERMIND_PUSH = 0xa51cE237FaFA3052D5d3308Df38A024724Bb1274; // Nethermind (push based)
    address internal constant PLASMA_DVN_HORIZON_PUSH = 0xd4CE45957FBCb88b868ad2c759C7DB9BC2741e56; // Horizen (push based)

    // --------------- Confirmations: send >= receive, see https://docs.layerzero.network/v2/developers/evm/configuration/dvn-executor-config

    /// @dev Minimum block confirmations to wait on Sonic
    uint64 internal constant MIN_BLOCK_CONFIRMATIONS_SEND_SONIC = 15;

    /// @dev Minimum block confirmations required on Avalanche
    uint64 internal constant MIN_BLOCK_CONFIRMATIONS_RECEIVE_TARGET = 10;

    /// @dev Minimum block confirmations to wait on Avalanche
    uint64 internal constant MIN_BLOCK_CONFIRMATIONS_SEND_TARGET = 15;

    /// @dev Minimum block confirmations required on Sonic
    uint64 internal constant MIN_BLOCK_CONFIRMATIONS_RECEIVE_SONIC = 10;

    /// @dev By default shared decimals (min decimals at all chains) is 6 for STBL
    uint internal constant SHARED_DECIMALS = 6;

    struct ChainConfig {
        uint fork;
        address multisig;

        /// @notice STBL-bridge
        address oapp;
        address xToken;

        uint32 endpointId;
        address endpoint;
        address sendLib;
        address receiveLib;
        address platform;
        address executor;

        address xTokenBridge;
    }

    //region ------------------------------------- Create contracts
    function setupSTBLBridged(Vm vm, BridgeTestLib.ChainConfig memory chain) internal returns (address) {
        vm.selectFork(chain.fork);

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new BridgedToken(chain.endpoint)));
        BridgedToken bridgedStbl = BridgedToken(address(proxy));
        bridgedStbl.initialize(address(chain.platform), "Stability STBL", "STBL");

        return address(bridgedStbl);
    }

    function setupStabilityOFTAdapterOnSonic(Vm vm, BridgeTestLib.ChainConfig memory sonic) internal returns (address) {
        vm.selectFork(sonic.fork);

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new StabilityOFTAdapter(SonicConstantsLib.TOKEN_STBL, sonic.endpoint)));
        StabilityOFTAdapter stblOFTAdapter = StabilityOFTAdapter(address(proxy));
        stblOFTAdapter.initialize(address(sonic.platform));

        return address(stblOFTAdapter);
    }

    //endregion ------------------------------------- Create contracts

    //region ------------------------------------- Chains
    function createConfigSonic(Vm vm, uint forkId) internal returns (BridgeTestLib.ChainConfig memory) {
        vm.selectFork(forkId);
        return BridgeTestLib.ChainConfig({
            fork: forkId,
            multisig: IPlatform(SonicConstantsLib.PLATFORM).multisig(),
            oapp: address(0), // to be set later
            endpointId: SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            endpoint: SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            sendLib: SonicConstantsLib.LAYER_ZERO_V2_SEND_ULN_302,
            receiveLib: SonicConstantsLib.LAYER_ZERO_V2_RECEIVE_ULN_302,
            platform: SonicConstantsLib.PLATFORM,
            executor: SonicConstantsLib.LAYER_ZERO_V2_EXECUTOR,
            xToken: SonicConstantsLib.TOKEN_XSTBL,
            xTokenBridge: address(0)
        });
    }

    function createConfigAvalanche(Vm vm, uint forkId) internal returns (BridgeTestLib.ChainConfig memory) {
        vm.selectFork(forkId);
        return BridgeTestLib.ChainConfig({
            fork: forkId,
            multisig: IPlatform(AvalancheConstantsLib.PLATFORM).multisig(),
            oapp: address(0), // to be set later
            endpointId: AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            endpoint: AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            sendLib: AvalancheConstantsLib.LAYER_ZERO_V2_SEND_ULN_302,
            receiveLib: AvalancheConstantsLib.LAYER_ZERO_V2_RECEIVE_ULN_302,
            platform: AvalancheConstantsLib.PLATFORM,
            executor: AvalancheConstantsLib.LAYER_ZERO_V2_EXECUTOR,
            xToken: address(0),
            xTokenBridge: address(0)
        });
    }

    function createConfigPlasma(Vm vm, uint forkId) internal returns (BridgeTestLib.ChainConfig memory) {
        vm.selectFork(forkId);
        return BridgeTestLib.ChainConfig({
            fork: forkId,
            multisig: IPlatform(PlasmaConstantsLib.PLATFORM).multisig(),
            oapp: address(0), // to be set later
            endpointId: PlasmaConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            endpoint: PlasmaConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            sendLib: PlasmaConstantsLib.LAYER_ZERO_V2_SEND_ULN_302,
            receiveLib: PlasmaConstantsLib.LAYER_ZERO_V2_RECEIVE_ULN_302,
            platform: PlasmaConstantsLib.PLATFORM,
            executor: PlasmaConstantsLib.LAYER_ZERO_V2_EXECUTOR,
            xToken: address(0),
            xTokenBridge: address(0)
        });
    }

    //endregion ------------------------------------- Chains

    //region ------------------------------------- Setup bridges
    function setUpSonicAvalanche(
        Vm vm,
        BridgeTestLib.ChainConfig memory sonic,
        BridgeTestLib.ChainConfig memory avalanche
    ) internal {
        // ------------------- Set up layer zero on Sonic
        _setupLayerZeroConfig(vm, sonic, avalanche, true);

        address[] memory requiredDVNs = new address[](1); // list must be sorted
        //            requiredDVNs[0] = SONIC_DVN_NETHERMIND_PULL;
        requiredDVNs[0] = SONIC_DVN_LAYER_ZERO_PULL;
        //            requiredDVNs[2] = SONIC_DVN_HORIZEN_PULL;
        _setSendConfig(vm, sonic, avalanche, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_SEND_SONIC);
        _setReceiveConfig(vm, avalanche, sonic, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_RECEIVE_TARGET);

        // ------------------- Set up receiving chain for Sonic:Avalanche
        _setupLayerZeroConfig(vm, avalanche, sonic, true);
        requiredDVNs = new address[](1); // list must be sorted
        requiredDVNs[0] = AVALANCHE_DVN_LAYER_ZERO_PULL;
        //            requiredDVNs[1] = AVALANCHE_DVN_NETHERMIND_PULL;
        //            requiredDVNs[2] = AVALANCHE_DVN_HORIZON_PULL;
        _setSendConfig(vm, avalanche, sonic, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_SEND_TARGET);
        _setReceiveConfig(vm, sonic, avalanche, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_RECEIVE_SONIC);

        // ------------------- set peers
        _setPeers(vm, sonic, avalanche);
    }

    function setUpSonicPlasma(
        Vm vm,
        BridgeTestLib.ChainConfig memory sonic,
        BridgeTestLib.ChainConfig memory plasma
    ) internal {
        // ------------------- Set up sending chain for Sonic:Plasma
        _setupLayerZeroConfig(vm, sonic, plasma, true);

        address[] memory requiredDVNs = new address[](1); // list must be sorted
        //            requiredDVNs[0] = SONIC_DVN_NETHERMIND_PULL;
        requiredDVNs[0] = SONIC_DVN_LAYER_ZERO_PUSH;
        //            requiredDVNs[2] = SONIC_DVN_HORIZEN_PULL;
        _setSendConfig(vm, sonic, plasma, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_SEND_SONIC);
        _setReceiveConfig(vm, plasma, sonic, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_RECEIVE_TARGET);

        // ------------------- Set up receiving chain for Sonic:Plasma
        _setupLayerZeroConfig(vm, plasma, sonic, true);
        requiredDVNs = new address[](1); // list must be sorted
        requiredDVNs[0] = PLASMA_DVN_LAYER_ZERO_PUSH;
        //        requiredDVNs[1] = PLASMA_DVN_NETHERMIND;
        //        requiredDVNs[2] = PLASMA_DVN_HORIZON;
        _setSendConfig(vm, plasma, sonic, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_SEND_TARGET);
        _setReceiveConfig(vm, plasma, sonic, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_RECEIVE_TARGET);

        // ------------------- set peers
        _setPeers(vm, sonic, plasma);
    }

    function setUpAvalanchePlasma(
        Vm vm,
        BridgeTestLib.ChainConfig memory avalanche,
        BridgeTestLib.ChainConfig memory plasma
    ) internal {
        // ------------------- Set up sending chain for Avalanche:Plasma
        _setupLayerZeroConfig(vm, avalanche, plasma, true);

        address[] memory requiredDVNs = new address[](1);
        requiredDVNs[0] = AVALANCHE_DVN_LAYER_ZERO_PUSH;
        _setSendConfig(vm, avalanche, plasma, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_SEND_TARGET);

        // ------------------- Set up receiving chain for Avalanche:Plasma
        _setupLayerZeroConfig(vm, plasma, avalanche, true);
        requiredDVNs = new address[](1);
        requiredDVNs[0] = PLASMA_DVN_LAYER_ZERO_PUSH;
        _setReceiveConfig(vm, plasma, avalanche, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_RECEIVE_TARGET);

        _setSendConfig(vm, plasma, avalanche, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_SEND_TARGET);

        // ------------------- set peers
        _setPeers(vm, avalanche, plasma);
    }

    //endregion ------------------------------------- Setup bridges

    //region ------------------------------------- Layer zero utils
    function _setupLayerZeroConfig(
        Vm vm,
        BridgeTestLib.ChainConfig memory src,
        BridgeTestLib.ChainConfig memory dst,
        bool setupBothWays
    ) internal {
        vm.selectFork(src.fork);

        if (src.sendLib != address(0)) {
            // Set send library for outbound messages
            vm.prank(src.multisig);
            ILayerZeroEndpointV2(src.endpoint)
                .setSendLibrary(
                    src.oapp, // OApp address
                    dst.endpointId, // Destination chain EID
                    src.sendLib // SendUln302 address
                );
        }

        // Set receive library for inbound messages
        if (setupBothWays) {
            vm.prank(src.multisig);
            ILayerZeroEndpointV2(src.endpoint)
                .setReceiveLibrary(
                    src.oapp, // OApp address
                    dst.endpointId, // Source chain EID
                    src.receiveLib, // ReceiveUln302 address
                    0 // Grace period for library switch
                );
        }
    }

    function _setPeers(Vm vm, BridgeTestLib.ChainConfig memory src, BridgeTestLib.ChainConfig memory dst) internal {
        // ------------------- Sonic: set up peer connection
        vm.selectFork(src.fork);

        vm.prank(src.multisig);
        IOAppCore(src.oapp).setPeer(dst.endpointId, bytes32(uint(uint160(address(dst.oapp)))));

        // ------------------- Avalanche: set up peer connection
        vm.selectFork(dst.fork);

        vm.prank(dst.multisig);
        IOAppCore(dst.oapp).setPeer(src.endpointId, bytes32(uint(uint160(address(src.oapp)))));
    }

    /// @notice Configures both ULN (DVN validators) and Executor for an OApp
    /// @param requiredDVNs  Array of DVN validator addresses
    /// @param confirmations  Minimum block confirmations
    function _setSendConfig(
        Vm vm,
        BridgeTestLib.ChainConfig memory src,
        BridgeTestLib.ChainConfig memory dst,
        address[] memory requiredDVNs,
        uint64 confirmations
    ) internal {
        vm.selectFork(src.fork);

        // ---------------------- ULN (DVN) configuration ----------------------
        UlnConfig memory uln = UlnConfig({
            confirmations: confirmations,
            requiredDVNCount: uint8(requiredDVNs.length),
            optionalDVNCount: type(uint8).max,
            requiredDVNs: requiredDVNs, // sorted list of required DVN addresses
            optionalDVNs: new address[](0),
            optionalDVNThreshold: 0
        });

        ExecutorConfig memory exec = ExecutorConfig({
            maxMessageSize: 256, // max bytes per cross-chain message
            executor: src.executor // address that pays destination execution fees
        });

        bytes memory encodedUln = abi.encode(uln);
        bytes memory encodedExec = abi.encode(exec);

        SetConfigParam[] memory params = new SetConfigParam[](2);
        params[0] = SetConfigParam({eid: dst.endpointId, configType: CONFIG_TYPE_EXECUTOR, config: encodedExec});
        params[1] = SetConfigParam({eid: dst.endpointId, configType: CONFIG_TYPE_ULN, config: encodedUln});

        vm.prank(src.multisig);
        ILayerZeroEndpointV2(src.endpoint).setConfig(src.oapp, src.sendLib, params);
    }

    /// @notice Configures ULN (DVN validators) for on receiving chain
    /// @dev https://docs.layerzero.network/v2/developers/evm/configuration/dvn-executor-config
    /// @param requiredDVNs  Array of DVN validator addresses
    /// @param confirmations Minimum block confirmations for ULN
    function _setReceiveConfig(
        Vm vm,
        BridgeTestLib.ChainConfig memory src,
        BridgeTestLib.ChainConfig memory dst,
        address[] memory requiredDVNs,
        uint64 confirmations
    ) internal {
        vm.selectFork(src.fork);

        // ---------------------- ULN (DVN) configuration ----------------------
        UlnConfig memory uln = UlnConfig({
            confirmations: confirmations, // Minimum block confirmations
            requiredDVNCount: uint8(requiredDVNs.length),
            optionalDVNCount: type(uint8).max,
            requiredDVNs: requiredDVNs, // sorted list of required DVN addresses
            optionalDVNs: new address[](0),
            optionalDVNThreshold: 0
        });

        SetConfigParam[] memory params = new SetConfigParam[](1);
        params[0] = SetConfigParam({eid: dst.endpointId, configType: CONFIG_TYPE_ULN, config: abi.encode(uln)});

        vm.prank(src.multisig);
        ILayerZeroEndpointV2(src.endpoint).setConfig(src.oapp, src.receiveLib, params);
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
        Vm vm,
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
            console.log("Executor maxMessageSize:", execConfig.maxMessageSize);
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
    function _extractSendMessage(Vm.Log[] memory logs) internal pure returns (bytes memory message, bytes32 guid) {
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

            // header length: 1 + 8 + 4 + 32 + 4 + 32 + 32 = 113
            uint start = 113;
            require(encodedPayload.length >= start, "encodedPayload too short");
            uint msgLen = encodedPayload.length - start;
            message = new bytes(msgLen);
            for (uint i = 0; i < msgLen; ++i) {
                message[i] = encodedPayload[start + i];
            }
        }

        assembly {
            guid := mload(add(encodedPayload, add(32, 81)))
        }
    }

    function _extractPayload(Vm.Log[] memory logs) internal pure returns (bytes memory encodedPayload) {
        bytes32 sig = keccak256("PacketSent(bytes,bytes,address)"); // PacketSent(bytes encodedPayload, bytes options, address sendLibrary)

        for (uint i; i < logs.length; ++i) {
            if (logs[i].topics[0] == sig) {
                (encodedPayload,,) = abi.decode(logs[i].data, (bytes, bytes, address));
                break;
            }
        }

        return encodedPayload;
    }

    /// @notice Extract ComposeSent message from emitted event
    function _extractComposeMessage(Vm
                .Log[] memory logs) internal pure returns (address from, address to, bytes memory message) {
        bytes32 sig = keccak256("ComposeSent(address,address,bytes32,uint16,bytes)"); // ComposeSent(address from, address to, bytes32 guid, uint16 index, bytes message)

        for (uint i; i < logs.length; ++i) {
            if (logs[i].topics[0] == sig) {
                (from, to,,, message) = abi.decode(logs[i].data, (address, address, bytes32, uint16, bytes));
                break;
            }
        }

        //        console.logBytes(message);
        return (from, to, message);
    }

    /// @notice Extract XTokenSent message from emitted event
    function _extractXTokenSentMessage(Vm
                .Log[] memory logs)
        internal
        pure
        returns (
            address userFrom,
            uint32 dstEid,
            uint amount,
            uint amountSentLD,
            bytes32 guidId,
            uint64 nonce,
            uint nativeFee
        )
    {
        // event XTokenSent(address indexed userFrom, uint32 indexed dstEid, uint amount, uint amountSentLD, bytes32 indexed guidId, uint64 nonce, uint nativeFee);
        bytes32 sig = keccak256("XTokenSent(address,uint32,uint256,uint256,bytes32,uint64,uint256)");

        for (uint i; i < logs.length; ++i) {
            if (logs[i].topics[0] != sig) continue;

            // extract indexed out of topics
            // topics = [sig, userFrom, dstEid, guidId]
            require(logs[i].topics.length >= 4, "not enough topics for indexed params");
            userFrom = address(uint160(uint(logs[i].topics[1])));
            dstEid = uint32(uint(logs[i].topics[2]));
            guidId = bytes32(logs[i].topics[3]);

            // extract all other params from data: amount, amountSentLD, nonce, nativeFee
            require(logs[i].data.length >= 32 * 4, "data too short for non-indexed params");
            (amount, amountSentLD, nonce, nativeFee) = abi.decode(logs[i].data, (uint, uint, uint64, uint));
            break;
        }

        return (userFrom, dstEid, amount, amountSentLD, guidId, nonce, nativeFee);
    }

    //endregion ------------------------------------- Layer zero utils

    /// @notice Empty function to exclude this test from coverage
    function test() public {}
}
