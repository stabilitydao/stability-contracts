// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console, Test, Vm} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IBridgedPriceOracle} from "../../src/interfaces/IBridgedPriceOracle.sol";
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
import { IOAppCore } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import { IOAppReceiver } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";
import {PriceAggregatorQApp} from "../../src/periphery/PriceAggregatorOApp.sol";
import {BridgedPriceOracle} from "../../src/periphery/BridgedPriceOracle.sol";
import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";

contract PriceAggregatorOAppTest is Test {
    using PacketV1Codec for bytes;
    using SafeERC20 for IERC20;

    uint private constant SONIC_FORK_BLOCK = 52228979; // Oct-28-2025 01:14:21 PM +UTC
    uint private constant AVALANCHE_FORK_BLOCK = 71037861; // Oct-28-2025 13:17:17 UTC
    uint private constant PLASMA_FORK_BLOCK = 5398928; // Nov-5-2025 07:38:59 UTC

    /// @dev Set to 0 for immediate switch, or block number for gradual migration
    uint private constant GRACE_PERIOD = 0;

    uint32 private constant CONFIG_TYPE_EXECUTOR = 1;
    uint32 private constant CONFIG_TYPE_ULN = 2;

    /// @dev Gas limit for executor lzReceive calls
    /// 2 mln => fee = 0.78 S
    /// 100_000 => fee = 0.36 S
    uint128 private constant GAS_LIMIT = 30_000;

    // --------------- DVN config: List of DVN providers must be equal on both chains (!)

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
    uint64 internal constant MIN_BLOCK_CONFIRMATIONS_RECEIVE = 10;

    PriceAggregatorQApp internal priceAggregatorOApp;
    BridgedPriceOracle internal bridgedPriceOracleAvalanche;
    BridgedPriceOracle internal bridgedPriceOraclePlasma;

    struct ChainConfig {
        uint fork;
        address multisig;
        address oapp;
        uint32 endpointId;
        address endpoint;
        address sendLib;
        address receiveLib;
        address platform;
        address executor;
    }

    ChainConfig internal sonic;
    ChainConfig internal avalanche;
    ChainConfig internal plasma;

    constructor() {
        {
            uint forkSonic = vm.createFork(vm.envString("SONIC_RPC_URL"), SONIC_FORK_BLOCK);
            uint forkAvalanche = vm.createFork(vm.envString("AVALANCHE_RPC_URL"), AVALANCHE_FORK_BLOCK);
            uint forkPlasma = vm.createFork(vm.envString("PLASMA_RPC_URL"), PLASMA_FORK_BLOCK);

            sonic = _createConfigSonic(forkSonic);
            avalanche = _createConfigAvalanche(forkAvalanche);
            plasma = _createConfigPlasma(forkPlasma);
        }

        // ------------------- Create adapter and bridged token
        priceAggregatorOApp = PriceAggregatorQApp(setupPriceAggregatorOAppOnSonic());
        bridgedPriceOracleAvalanche = BridgedPriceOracle(setupBridgedPriceOracle(avalanche));
        bridgedPriceOraclePlasma = BridgedPriceOracle(setupBridgedPriceOracle(plasma));

        sonic.oapp = address(priceAggregatorOApp);
        avalanche.oapp = address(bridgedPriceOracleAvalanche);
        plasma.oapp = address(bridgedPriceOraclePlasma);

        // ------------------- Set up Sonic:Avalanche
        {
            // ------------------- Set up sending chain for Sonic:Avalanche
            _setupLayerZeroConfig(sonic, avalanche, false);

            address[] memory requiredDVNs = new address[](1); // list must be sorted
//            requiredDVNs[0] = SONIC_DVN_NETHERMIND_PULL;
            requiredDVNs[0] = SONIC_DVN_LAYER_ZERO_PULL;
//            requiredDVNs[2] = SONIC_DVN_HORIZEN_PULL;
            _setSendConfig(sonic, avalanche, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_SEND_SONIC);

            // ------------------- Set up receiving chain for Sonic:Avalanche
            _setupLayerZeroConfig(avalanche, sonic, false);
            requiredDVNs = new address[](1); // list must be sorted
            requiredDVNs[0] = AVALANCHE_DVN_LAYER_ZERO_PULL;
//            requiredDVNs[1] = AVALANCHE_DVN_NETHERMIND_PULL;
//            requiredDVNs[2] = AVALANCHE_DVN_HORIZON_PULL;
            _setReceiveConfig(avalanche, sonic, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_RECEIVE);

            // ------------------- set peers
            _setPeers(sonic, avalanche);
        }

        // ------------------- Set up Sonic:Plasma
        {
            // ------------------- Set up sending chain for Sonic:Plasma
            _setupLayerZeroConfig(sonic, plasma, false);

            address[] memory requiredDVNs = new address[](1); // list must be sorted
//            requiredDVNs[0] = SONIC_DVN_NETHERMIND_PULL;
            requiredDVNs[0] = SONIC_DVN_LAYER_ZERO_PUSH;
//            requiredDVNs[2] = SONIC_DVN_HORIZEN_PULL;
            _setSendConfig(sonic, plasma, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_SEND_SONIC);

            // ------------------- Set up receiving chain for Sonic:Plasma
            _setupLayerZeroConfig(plasma, sonic, false);
            requiredDVNs = new address[](1); // list must be sorted
            requiredDVNs[0] = PLASMA_DVN_LAYER_ZERO_PUSH;
            //        requiredDVNs[1] = PLASMA_DVN_NETHERMIND;
            //        requiredDVNs[2] = PLASMA_DVN_HORIZON;
            _setReceiveConfig(plasma, sonic, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_RECEIVE);

            // ------------------- set peers
            _setPeers(sonic, plasma);
        }
    }

    //region ------------------------------------- Unit tests for PriceAggregatorQApp
    function testViewPriceAggregatorQApp() public {
        vm.selectFork(sonic.fork);

        //        console.log("erc7201:stability.PriceAggregatorQApp");
        //        console.logBytes32(
        //            keccak256(abi.encode(uint(keccak256("erc7201:stability.PriceAggregatorQApp")) - 1)) & ~bytes32(uint(0xff))
        //        );

        assertEq(priceAggregatorOApp.entity(), SonicConstantsLib.TOKEN_STBL, "stbl");
        assertEq(priceAggregatorOApp.platform(), SonicConstantsLib.PLATFORM, "priceAggregatorQApp - platform");
        assertEq(priceAggregatorOApp.owner(), sonic.multisig, "priceAggregatorQApp - owner");
    }

    function testWhitelist() public {
        vm.selectFork(sonic.fork);

        vm.prank(address(this));
        vm.expectRevert(IControllable.NotOperator.selector);
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

        assertEq(priceAggregatorOApp.peers(avalanche.endpointId), bytes32(uint(uint160(address(bridgedPriceOracleAvalanche)))));
    }

    function testLzReceiveUnsuppoted() public {
        vm.selectFork(sonic.fork);

        Origin memory origin = Origin({
            srcEid: AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            sender: bytes32(uint(uint160(address(bridgedPriceOracleAvalanche)))),
            nonce: 1
        });

        vm.prank(sonic.endpoint);
        vm.expectRevert(IPriceAggregatorQApp.UnsupportedOperation.selector);
        priceAggregatorOApp.lzReceive(
            origin,
            bytes32(0), // guid: actual value doesn't matter
            hex"00", // empty message
            address(0), // executor
            "" // extraData
        );
    }

    //endregion ------------------------------------- Unit tests for PriceAggregatorQApp

    //region ------------------------------------- Unit tests for BridgedPriceOracleAvalanche
    function testViewBridgedPriceOracle() public {
        vm.selectFork(avalanche.fork);

        //        console.log("erc7201:stability.BridgedPriceOracle");
        //        console.logBytes32(
        //            keccak256(abi.encode(uint(keccak256("erc7201:stability.BridgedPriceOracle")) - 1)) & ~bytes32(uint(0xff))
        //        );

        assertEq(bridgedPriceOracleAvalanche.decimals(), 8, "decimals in aave price oracle is 8");
        assertEq(bridgedPriceOracleAvalanche.platform(), AvalancheConstantsLib.PLATFORM, "bridgedPriceOracle - platform");
        assertEq(bridgedPriceOracleAvalanche.owner(), avalanche.multisig, "bridgedPriceOracle - owner");
    }

    function testBridgedPriceOraclePeers() public {
        vm.selectFork(avalanche.fork);

        vm.prank(address(this));
        vm.expectRevert();
        bridgedPriceOracleAvalanche.setPeer(sonic.endpointId, bytes32(uint(uint160(address(priceAggregatorOApp)))));

        vm.prank(avalanche.multisig);
        bridgedPriceOracleAvalanche.setPeer(sonic.endpointId, bytes32(uint(uint160(address(priceAggregatorOApp)))));

        assertEq(
            bridgedPriceOracleAvalanche.peers(sonic.endpointId),
            bytes32(uint(uint160(address(priceAggregatorOApp))))
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
        vm.expectRevert(IPriceAggregatorQApp.NotWhitelisted.selector);
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
        bytes memory message = _extractPayload(vm.getRecordedLogs());

        // ------------------ Avalanche: simulate message reception
        vm.selectFork(avalanche.fork);

        Origin memory origin = Origin({
            srcEid: sonic.endpointId,
            sender: bytes32(uint(uint160(address(priceAggregatorOApp)))),
            nonce: 1
        });

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

    //endregion ------------------------------------- Send price from Sonic to Avalanche

    //region ------------------------------------- Tests implementation
    function _testSendPriceToDest(ChainConfig memory dest) public {
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

    function _sendPriceFromSonicToDest(address sender, ChainConfig memory dest) internal returns (uint price, uint timestamp) {
        vm.selectFork(sonic.fork);

        // ------------------- Send a message with new price to target chain
        bytes memory options = OptionsBuilder.addExecutorLzReceiveOption(OptionsBuilder.newOptions(), GAS_LIMIT, 0);

        MessagingFee memory msgFee = priceAggregatorOApp.quotePriceMessage(dest.endpointId, options, false);

        vm.recordLogs();

        vm.prank(sender);
        priceAggregatorOApp.sendPriceMessage{value: msgFee.nativeFee}(dest.endpointId, options, msgFee);
        bytes memory message = _extractPayload(vm.getRecordedLogs());

        // ------------------ Target chain: simulate message reception
        vm.selectFork(dest.fork);

        Origin memory origin = Origin({
            srcEid: sonic.endpointId,
            sender: bytes32(uint(uint160(address(priceAggregatorOApp)))),
            nonce: 1
        });

        uint gas = gasleft();
        vm.prank(dest.endpoint);
        IOAppReceiver(dest.oapp).lzReceive(
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

    function setupPriceAggregatorOAppOnSonic() internal returns (address) {
        vm.selectFork(sonic.fork);

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new PriceAggregatorQApp(sonic.endpoint)));
        PriceAggregatorQApp _priceAggregatorQApp = PriceAggregatorQApp(address(proxy));
        _priceAggregatorQApp.initialize(sonic.platform, SonicConstantsLib.TOKEN_STBL);

        assertEq(_priceAggregatorQApp.owner(), sonic.multisig, "multisigSonic is owner");

        return address(_priceAggregatorQApp);
    }

    function setupBridgedPriceOracle(ChainConfig memory chain) internal returns (address) {
        vm.selectFork(chain.fork);

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new BridgedPriceOracle(chain.endpoint)));
        BridgedPriceOracle _bridgedPriceOracle = BridgedPriceOracle(address(proxy));
        _bridgedPriceOracle.initialize(address(chain.platform));

        assertEq(_bridgedPriceOracle.owner(), chain.multisig, "multisig is owner");

        return address(_bridgedPriceOracle);
    }

    function _setupLayerZeroConfig(ChainConfig memory src, ChainConfig memory dst, bool setupBothWays) internal {
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
                    src.endpointId, // Source chain EID
                    src.receiveLib, // ReceiveUln302 address
                    GRACE_PERIOD // Grace period for library switch
                );
        }
    }

    function _setPeers(ChainConfig memory src, ChainConfig memory dst) internal {
        // ------------------- Sonic: set up peer connection
        vm.selectFork(src.fork);

        vm.prank(src.multisig);
        IOAppCore(src.oapp).setPeer(
            dst.endpointId, bytes32(uint(uint160(address(dst.oapp))))
        );

        // ------------------- Avalanche: set up peer connection
        vm.selectFork(dst.fork);

        vm.prank(dst.multisig);
        IOAppCore(dst.oapp).setPeer(
            src.endpointId, bytes32(uint(uint160(address(src.oapp))))
        );
    }

    /// @notice Configures both ULN (DVN validators) and Executor for an OApp
    /// @param requiredDVNs  Array of DVN validator addresses
    /// @param confirmations  Minimum block confirmations
    function _setSendConfig(ChainConfig memory src, ChainConfig memory dst, address[] memory requiredDVNs, uint64 confirmations) internal {
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
            maxMessageSize: 32, // max bytes per cross-chain message
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
    function _setReceiveConfig(ChainConfig memory src, ChainConfig memory dst, address[] memory requiredDVNs, uint64 confirmations) internal {
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

    //region ------------------------------------- Chains
    function _createConfigSonic(uint forkId) internal returns (ChainConfig memory) {
        vm.selectFork(forkId);
        return ChainConfig({
            fork: forkId,
            multisig: IPlatform(SonicConstantsLib.PLATFORM).multisig(),
            oapp: address(0), // to be set later
            endpointId: SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            endpoint: SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            sendLib: SonicConstantsLib.LAYER_ZERO_V2_SEND_ULN_302,
            receiveLib: SonicConstantsLib.LAYER_ZERO_V2_RECEIVE_ULN_302,
            platform: SonicConstantsLib.PLATFORM,
            executor: SonicConstantsLib.LAYER_ZERO_V2_EXECUTOR
        });
    }

    function _createConfigAvalanche(uint forkId) internal returns (ChainConfig memory) {
        vm.selectFork(forkId);
        return ChainConfig({
            fork: forkId,
            multisig: IPlatform(AvalancheConstantsLib.PLATFORM).multisig(),
            oapp: address(0), // to be set later
            endpointId: AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            endpoint: AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            sendLib: AvalancheConstantsLib.LAYER_ZERO_V2_SEND_ULN_302,
            receiveLib: AvalancheConstantsLib.LAYER_ZERO_V2_RECEIVE_ULN_302,
            platform: AvalancheConstantsLib.PLATFORM,
            executor: AvalancheConstantsLib.LAYER_ZERO_V2_EXECUTOR
        });
    }

    function _createConfigPlasma(uint forkId) internal returns (ChainConfig memory) {
        vm.selectFork(forkId);
        return ChainConfig({
            fork: forkId,
            multisig: IPlatform(PlasmaConstantsLib.PLATFORM).multisig(),
            oapp: address(0), // to be set later
            endpointId: PlasmaConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            endpoint: PlasmaConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            sendLib: PlasmaConstantsLib.LAYER_ZERO_V2_SEND_ULN_302,
            receiveLib: PlasmaConstantsLib.LAYER_ZERO_V2_RECEIVE_ULN_302,
            platform: PlasmaConstantsLib.PLATFORM,
            executor: PlasmaConstantsLib.LAYER_ZERO_V2_EXECUTOR
        });
    }

    //endregion ------------------------------------- Chains
}
