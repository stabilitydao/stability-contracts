// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console, Test, Vm} from "forge-std/Test.sol";
import {BridgedToken} from "../../src/tokenomics/BridgedToken.sol";
import {StabilityOFTAdapter} from "../../src/tokenomics/StabilityOFTAdapter.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IOFTPausable} from "../../src/interfaces/IOFTPausable.sol";
import {IOAppCore} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppCore.sol";
import {IOAppReceiver} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {AvalancheConstantsLib} from "../../chains/avalanche/AvalancheConstantsLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {IOFT} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";
// import {OFTMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {ExecutorConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
// import {InboundPacket, PacketDecoder} from "@layerzerolabs/lz-evm-protocol-v2/../oapp/contracts/precrime/libs/Packet.sol";
import {PacketV1Codec} from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";

contract BridgedTokenTest is Test {
    using OptionsBuilder for bytes;
    using PacketV1Codec for bytes;
    using SafeERC20 for IERC20;

    //region ------------------------------------- Constants, data types, variables
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
    uint128 private constant GAS_LIMIT = 60_000;

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

    StabilityOFTAdapter internal adapter;
    BridgedToken internal bridgedTokenAvalanche;
    BridgedToken internal bridgedTokenPlasma;

    struct ChainResults {
        uint balanceSenderSTBL;
        uint balanceContractSTBL;
        uint balanceReceiverSTBL;
        uint totalSupplySTBL;
        uint balanceSenderEther;
    }

    struct Results {
        ChainResults srcBefore;
        ChainResults targetBefore;
        ChainResults srcAfter;
        ChainResults targetAfter;
        uint nativeFee;
    }

    struct TestCaseSendToTarget {
        address sender;
        uint sendAmount;
        uint initialBalance;
        address receiver;
    }

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
    //endregion ------------------------------------- Constants, data types, variables

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
        adapter = StabilityOFTAdapter(setupStabilityOFTAdapterOnSonic());
        bridgedTokenAvalanche = BridgedToken(setupSTBLBridged(avalanche));
        bridgedTokenPlasma = BridgedToken(setupSTBLBridged(plasma));

        sonic.oapp = address(adapter);
        avalanche.oapp = address(bridgedTokenAvalanche);
        plasma.oapp = address(bridgedTokenPlasma);

        // ------------------- Set up Sonic:Avalanche
        {
            // ------------------- Set up layer zero on Sonic
            _setupLayerZeroConfig(sonic, avalanche, true);

            address[] memory requiredDVNs = new address[](1); // list must be sorted
            //            requiredDVNs[0] = SONIC_DVN_NETHERMIND_PULL;
            requiredDVNs[0] = SONIC_DVN_LAYER_ZERO_PULL;
            //            requiredDVNs[2] = SONIC_DVN_HORIZEN_PULL;
            _setSendConfig(sonic, avalanche, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_SEND_SONIC);
            _setReceiveConfig(avalanche, sonic, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_RECEIVE_TARGET);

            // ------------------- Set up receiving chain for Sonic:Avalanche
            _setupLayerZeroConfig(avalanche, sonic, true);
            requiredDVNs = new address[](1); // list must be sorted
            requiredDVNs[0] = AVALANCHE_DVN_LAYER_ZERO_PULL;
            //            requiredDVNs[1] = AVALANCHE_DVN_NETHERMIND_PULL;
            //            requiredDVNs[2] = AVALANCHE_DVN_HORIZON_PULL;
            _setSendConfig(avalanche, sonic, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_SEND_TARGET);
            _setReceiveConfig(sonic, avalanche, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_RECEIVE_SONIC);

            // ------------------- set peers
            _setPeers(sonic, avalanche);
        }

        // ------------------- Set up Sonic:Plasma
        {
            // ------------------- Set up sending chain for Sonic:Plasma
            _setupLayerZeroConfig(sonic, plasma, true);

            address[] memory requiredDVNs = new address[](1); // list must be sorted
            //            requiredDVNs[0] = SONIC_DVN_NETHERMIND_PULL;
            requiredDVNs[0] = SONIC_DVN_LAYER_ZERO_PUSH;
            //            requiredDVNs[2] = SONIC_DVN_HORIZEN_PULL;
            _setSendConfig(sonic, plasma, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_SEND_SONIC);
            _setReceiveConfig(plasma, sonic, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_RECEIVE_TARGET);

            // ------------------- Set up receiving chain for Sonic:Plasma
            _setupLayerZeroConfig(plasma, sonic, true);
            requiredDVNs = new address[](1); // list must be sorted
            requiredDVNs[0] = PLASMA_DVN_LAYER_ZERO_PUSH;
            //        requiredDVNs[1] = PLASMA_DVN_NETHERMIND;
            //        requiredDVNs[2] = PLASMA_DVN_HORIZON;
            _setSendConfig(plasma, sonic, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_SEND_TARGET);
            _setReceiveConfig(plasma, sonic, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_RECEIVE_TARGET);

            // ------------------- set peers
            _setPeers(sonic, plasma);
        }

        // ------------------- Set up Avalanche:Plasma
        {
            // ------------------- Set up sending chain for Avalanche:Plasma
            _setupLayerZeroConfig(avalanche, plasma, true);

            address[] memory requiredDVNs = new address[](1);
            requiredDVNs[0] = AVALANCHE_DVN_LAYER_ZERO_PUSH;
            _setSendConfig(avalanche, plasma, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_SEND_TARGET);

            // ------------------- Set up receiving chain for Avalanche:Plasma
            _setupLayerZeroConfig(plasma, avalanche, true);
            requiredDVNs = new address[](1);
            requiredDVNs[0] = PLASMA_DVN_LAYER_ZERO_PUSH;
            _setReceiveConfig(plasma, avalanche, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_RECEIVE_TARGET);

            _setSendConfig(plasma, avalanche, requiredDVNs, MIN_BLOCK_CONFIRMATIONS_SEND_TARGET);

            // ------------------- set peers
            _setPeers(avalanche, plasma);
        }
    }

    //region ------------------------------------- Unit tests for bridgedTokenAvalanche
    function testConfigBridgedToken() internal {
        //        _getConfig(
        //            avalanche.fork,
        //            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT,
        //            address(bridgedToken),
        //            AvalancheConstantsLib.LAYER_ZERO_V2_RECEIVE_ULN_302,
        //            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
        //            CONFIG_TYPE_EXECUTOR
        //        );

        _getConfig(
            avalanche.fork,
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            address(bridgedTokenAvalanche),
            AvalancheConstantsLib.LAYER_ZERO_V2_RECEIVE_ULN_302,
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            CONFIG_TYPE_ULN
        );
    }

    function testViewBridgedToken() public {
        vm.selectFork(avalanche.fork);

        //        console.log("erc7201:stability.BridgedToken");
        //        console.logBytes32(
        //            keccak256(abi.encode(uint(keccak256("erc7201:stability.BridgedToken")) - 1)) & ~bytes32(uint(0xff))
        //        );

        assertEq(bridgedTokenAvalanche.name(), "Stability STBL");
        assertEq(bridgedTokenAvalanche.symbol(), "STBL");
        assertEq(bridgedTokenAvalanche.decimals(), 18);

        assertEq(bridgedTokenAvalanche.platform(), avalanche.platform, "BridgedToken - platform");
        assertEq(bridgedTokenAvalanche.owner(), avalanche.multisig, "BridgedToken - owner");
        assertEq(bridgedTokenAvalanche.token(), address(bridgedTokenAvalanche), "BridgedToken - token");
        assertEq(bridgedTokenAvalanche.approvalRequired(), false, "BridgedToken - approvalRequired");
        assertEq(bridgedTokenAvalanche.sharedDecimals(), SHARED_DECIMALS, "BridgedToken - shared decimals");
    }

    function testBridgedTokenPause() public {
        vm.selectFork(avalanche.fork);

        assertEq(bridgedTokenAvalanche.paused(address(this)), false);

        vm.prank(avalanche.multisig);
        bridgedTokenAvalanche.setPaused(address(this), true);
        assertEq(bridgedTokenAvalanche.paused(address(this)), true);

        vm.prank(address(this));
        vm.expectRevert(IControllable.NotOperator.selector);
        bridgedTokenAvalanche.setPaused(address(this), true);

        vm.prank(avalanche.multisig);
        bridgedTokenAvalanche.setPaused(address(this), false);
        assertEq(bridgedTokenAvalanche.paused(address(this)), false);
    }

    function testBridgedTokenSetPeers() public {
        vm.selectFork(sonic.fork);

        vm.prank(address(this));
        vm.expectRevert();
        adapter.setPeer(
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, bytes32(uint(uint160(address(bridgedTokenAvalanche))))
        );

        vm.prank(sonic.multisig);
        adapter.setPeer(
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, bytes32(uint(uint160(address(bridgedTokenAvalanche))))
        );
    }

    //endregion ------------------------------------- Unit tests for bridgetSTBL

    //region ------------------------------------- Unit tests for StabilityOFTAdapter
    function testViewStabilityOFTAdapter() public {
        vm.selectFork(sonic.fork);

        //        console.log("erc7201:stability.StabilityOFTAdapter");
        //        console.logBytes32(
        //            keccak256(abi.encode(uint(keccak256("erc7201:stability.StabilityOFTAdapter")) - 1)) & ~bytes32(uint(0xff))
        //        );

        assertEq(adapter.platform(), SonicConstantsLib.PLATFORM, "StabilityOFTAdapter - platform");
        assertEq(adapter.owner(), sonic.multisig, "StabilityOFTAdapter - owner");
        assertEq(adapter.token(), SonicConstantsLib.TOKEN_STBL, "StabilityOFTAdapter - token");
        assertEq(adapter.approvalRequired(), true, "StabilityOFTAdapter - approvalRequired");
        assertEq(adapter.sharedDecimals(), SHARED_DECIMALS, "StabilityOFTAdapter - shared decimals");
    }

    function testConfigStabilityOFTAdapter() internal {
        _getConfig(
            sonic.fork,
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            address(adapter),
            SonicConstantsLib.LAYER_ZERO_V2_SEND_ULN_302,
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            CONFIG_TYPE_EXECUTOR
        );

        //        _getConfig(
        //            sonic.fork,
        //            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT,
        //            address(adapter),
        //            SonicConstantsLib.LAYER_ZERO_V2_SEND_ULN_302,
        //            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
        //            CONFIG_TYPE_ULN
        //        );
    }

    function testAdapterPause() public {
        vm.selectFork(sonic.fork);

        assertEq(adapter.paused(address(this)), false);

        vm.prank(sonic.multisig);
        adapter.setPaused(address(this), true);
        assertEq(adapter.paused(address(this)), true);

        vm.prank(address(this));
        vm.expectRevert(IControllable.NotOperator.selector);
        adapter.setPaused(address(this), true);

        vm.prank(sonic.multisig);
        adapter.setPaused(address(this), false);
        assertEq(adapter.paused(address(this)), false);
    }

    function testStabilityOFTAdapterPeers() public {
        vm.selectFork(avalanche.fork);

        vm.prank(address(this));
        vm.expectRevert();
        bridgedTokenAvalanche.setPeer(
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, bytes32(uint(uint160(address(adapter))))
        );

        vm.prank(avalanche.multisig);
        bridgedTokenAvalanche.setPeer(
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, bytes32(uint(uint160(address(adapter))))
        );
    }

    //endregion ------------------------------------- Unit tests for StabilityOFTAdapter

    //region ------------------------------------- Test: Send from Sonic to Avalanche
    function fixtureDataSA() public returns (TestCaseSendToTarget[] memory) {
        TestCaseSendToTarget[] memory tests = new TestCaseSendToTarget[](3);

        tests[0] = TestCaseSendToTarget({
            sender: address(this), sendAmount: 1e18, initialBalance: 800e18, receiver: address(this)
        });

        tests[1] = TestCaseSendToTarget({
            sender: address(this), sendAmount: 799_000e18, initialBalance: 800_000e18, receiver: address(this)
        });

        tests[2] = TestCaseSendToTarget({
            sender: address(this), sendAmount: 799_000e18, initialBalance: 800_000e18, receiver: makeAddr("111")
        });

        return tests;
    }

    function tableDataSATest(TestCaseSendToTarget memory dataSA) public {
        _testSendToAvalancheAndCheck(dataSA.sender, dataSA.sendAmount, dataSA.initialBalance, dataSA.receiver);
    }
    //endregion ------------------------------------- Test: Send from Sonic to Avalanche

    //region ------------------------------------- Test: Send from Sonic to target and back

    function testSendFromSonicToAvalancheAndBack() public {
        // ------------- There are 4 users: A, B, C, D
        address userA = makeAddr("A");
        address userB = makeAddr("B");
        address userC = makeAddr("C");
        address userD = makeAddr("D");

        // ------------- Sonic.A => Avalanche.B
        Results memory r1 = _testSendFromSonicToBridged(userA, 157e18, 357e18, userB, avalanche);

        assertEq(r1.srcAfter.balanceSenderSTBL, 357e18 - 157e18, "A balance 1");
        assertEq(r1.targetAfter.balanceReceiverSTBL, 157e18, "B balance 1");

        // ------------- Avalanche.B => Avalanche.C
        vm.selectFork(avalanche.fork);
        vm.prank(userB);
        IERC20(bridgedTokenAvalanche).safeTransfer(userC, 100e18);

        assertEq(bridgedTokenAvalanche.balanceOf(userB), 57e18, "B balance 2");
        assertEq(bridgedTokenAvalanche.balanceOf(userC), 100e18, "C balance 2");

        // ------------- Avalanche.C => Sonic.D
        Results memory r2 = _testSendFromBridgedToSonic(userC, 80e18, userD, avalanche);

        assertEq(r2.srcAfter.balanceSenderSTBL, 20e18, "C balance 3");
        assertEq(r2.targetAfter.balanceReceiverSTBL, 80e18, "D balance 3");

        assertEq(r2.srcAfter.totalSupplySTBL, 57e18 + 20e18, "total supply after all transfers: b + c");
        assertEq(r2.targetAfter.totalSupplySTBL, r1.srcBefore.totalSupplySTBL, "total supply of STBL wasn't changed");
    }

    function testSendFromSonicToPlasmaAndBack() public {
        // ------------- There are 4 users: A, B, C, D
        address userA = makeAddr("A");
        address userB = makeAddr("B");
        address userC = makeAddr("C");
        address userD = makeAddr("D");

        // ------------- Sonic.A => Plasma.B
        Results memory r1 = _testSendFromSonicToBridged(userA, 157e18, 357e18, userB, plasma);

        assertEq(r1.srcAfter.balanceSenderSTBL, 357e18 - 157e18, "A balance 1");
        assertEq(r1.targetAfter.balanceReceiverSTBL, 157e18, "B balance 1");

        // ------------- Plasma.B => Plasma.C
        vm.selectFork(plasma.fork);
        vm.prank(userB);
        IERC20(plasma.oapp).safeTransfer(userC, 100e18);

        assertEq(IERC20(plasma.oapp).balanceOf(userB), 57e18, "B balance 2");
        assertEq(IERC20(plasma.oapp).balanceOf(userC), 100e18, "C balance 2");

        // ------------- Plasma.C => Sonic.D
        Results memory r2 = _testSendFromBridgedToSonic(userC, 80e18, userD, plasma);

        assertEq(r2.srcAfter.balanceSenderSTBL, 20e18, "C balance 3");
        assertEq(r2.targetAfter.balanceReceiverSTBL, 80e18, "D balance 3");

        assertEq(r2.srcAfter.totalSupplySTBL, 57e18 + 20e18, "total supply after all transfers: b + c");
        assertEq(r2.targetAfter.totalSupplySTBL, r1.srcBefore.totalSupplySTBL, "total supply of STBL wasn't changed");
    }

    function testSendFromAvalancheToPlasmaAndBack() public {
        // ------------- There are 4 users: A, B, C, D
        address userA = makeAddr("A");
        address userB = makeAddr("B");
        address userC = makeAddr("C");

        // ------------- Sonic.A => Plasma.B
        Results memory r1 = _testSendFromSonicToBridged(userA, 157e18, 357e18, userB, plasma);

        assertEq(r1.srcAfter.balanceSenderSTBL, 357e18 - 157e18, "A balance 1");
        assertEq(r1.targetAfter.balanceReceiverSTBL, 157e18, "B balance 1");

        // ------------- Plasma.B => Avalanche.C
        Results memory r2 = _testSendFromBridgedToBridged(userB, 57e18, userC, plasma, avalanche);

        assertEq(r2.srcAfter.balanceSenderSTBL, 100e18, "B balance on plasma 2");
        assertEq(r2.targetAfter.balanceReceiverSTBL, 57e18, "C balance on avalanche 2");

        // ------------- Avalanche.C => Plasma.C
        Results memory r3 = _testSendFromBridgedToBridged(userC, 27e18, userC, avalanche, plasma);
        //        _showResults(r3.srcBefore);
        //        _showResults(r3.srcAfter);
        //        _showResults(r3.targetBefore);
        //        _showResults(r3.targetAfter);

        assertEq(r3.srcAfter.balanceReceiverSTBL, 30e18, "C balance on avalanche 3");
        assertEq(r3.targetAfter.balanceSenderSTBL, 27e18, "C balance on plasma 3");

        // ------------- Avalanche.C => Sonic.A
        Results memory r4 = _testSendFromBridgedToSonic(userC, 20e18, userC, avalanche);

        assertEq(r4.srcAfter.balanceReceiverSTBL, 10e18, "C balance on Avalanche 4");
        assertEq(r4.targetAfter.balanceSenderSTBL, 20e18, "C balance on Sonic 4");
    }

    function testUserPausedOnSonic() public {
        address userF = makeAddr("A");
        address userA = makeAddr("D");

        // ------------- Prepare balances and pause the user on Sonic
        _testSendFromSonicToBridged(userF, 100e18, 500e18, userF, avalanche);

        vm.selectFork(sonic.fork);
        deal(SonicConstantsLib.TOKEN_STBL, userA, 300e18);

        assertEq(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(userF), 400e18, "Sonic.F: initial balance");
        assertEq(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(userA), 300e18, "Sonic.A: initial balance");

        vm.prank(sonic.multisig);
        adapter.setPaused(userF, true);

        vm.selectFork(avalanche.fork);
        vm.prank(userF);
        IERC20(bridgedTokenAvalanche).safeTransfer(userA, 70e18);

        assertEq(bridgedTokenAvalanche.balanceOf(userF), 30e18, "Avalanche.F: initial balance");
        assertEq(bridgedTokenAvalanche.balanceOf(userA), 70e18, "Avalanche.A: initial balance");

        // ----------- Tests
        _testSendToAvalancheOnPause(userF, 1e18, userA, false); // forbidden
        _testSendToAvalancheOnPause(userA, 1e18, userF, true); // allowed
        _testSendToSonicOnPause(userF, 1e18, userA, true); // allowed
        _testSendToSonicOnPause(userA, 1e18, userF, true); // allowed
    }

    function testUserPausedOnAvalanche() public {
        address userF = makeAddr("A");
        address userA = makeAddr("D");

        // ------------- Prepare balances and pause the user on Avalanche
        _testSendFromSonicToBridged(userF, 100e18, 500e18, userF, avalanche);

        vm.selectFork(sonic.fork);
        deal(SonicConstantsLib.TOKEN_STBL, userA, 300e18);

        assertEq(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(userF), 400e18, "Sonic.F: initial balance");
        assertEq(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(userA), 300e18, "Sonic.A: initial balance");

        vm.selectFork(avalanche.fork);
        vm.prank(userF);
        IERC20(bridgedTokenAvalanche).safeTransfer(userA, 70e18);

        assertEq(bridgedTokenAvalanche.balanceOf(userF), 30e18, "Avalanche.F: initial balance");
        assertEq(bridgedTokenAvalanche.balanceOf(userA), 70e18, "Avalanche.A: initial balance");

        vm.prank(avalanche.multisig);
        bridgedTokenAvalanche.setPaused(userF, true);

        // ----------- Tests
        _testSendToAvalancheOnPause(userF, 1e18, userA, true); // allowed
        _testSendToAvalancheOnPause(userA, 1e18, userF, true); // allowed
        _testSendToSonicOnPause(userF, 1e18, userA, false); // forbidden
        _testSendToSonicOnPause(userA, 1e18, userF, true); // allowed
    }

    function testUserPausedOnBothChains() public {
        address userF = makeAddr("A");
        address userA = makeAddr("D");

        // ------------- Prepare balance and pause the user on both chains
        _testSendFromSonicToBridged(userF, 100e18, 500e18, userF, avalanche);

        vm.selectFork(sonic.fork);
        deal(SonicConstantsLib.TOKEN_STBL, userA, 300e18);

        assertEq(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(userF), 400e18, "Sonic.F: initial balance");
        assertEq(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(userA), 300e18, "Sonic.A: initial balance");

        vm.prank(sonic.multisig);
        adapter.setPaused(userF, true);

        vm.selectFork(avalanche.fork);
        vm.prank(userF);
        IERC20(bridgedTokenAvalanche).safeTransfer(userA, 70e18);

        assertEq(bridgedTokenAvalanche.balanceOf(userF), 30e18, "Avalanche.F: initial balance");
        assertEq(bridgedTokenAvalanche.balanceOf(userA), 70e18, "Avalanche.A: initial balance");

        vm.prank(avalanche.multisig);
        bridgedTokenAvalanche.setPaused(userF, true);

        // ----------- Tests
        _testSendToAvalancheOnPause(userF, 1e18, userA, false); // forbidden
        _testSendToAvalancheOnPause(userA, 1e18, userF, true); // allowed
        _testSendToSonicOnPause(userF, 1e18, userA, false); // forbidden
        _testSendToSonicOnPause(userA, 1e18, userF, true); // allowed
    }

    function testContractsPausedOnBothChains() public {
        address userF = makeAddr("A");
        address userA = makeAddr("D");

        // ------------- Prepare balance and pause the user on both chains
        _testSendFromSonicToBridged(userF, 100e18, 500e18, userF, avalanche);

        vm.selectFork(sonic.fork);
        deal(SonicConstantsLib.TOKEN_STBL, userA, 300e18);

        assertEq(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(userF), 400e18, "Sonic.F: initial balance");
        assertEq(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(userA), 300e18, "Sonic.A: initial balance");

        vm.prank(sonic.multisig);
        adapter.setPaused(address(adapter), true);

        vm.selectFork(avalanche.fork);
        vm.prank(userF);
        IERC20(bridgedTokenAvalanche).safeTransfer(userA, 70e18);

        assertEq(bridgedTokenAvalanche.balanceOf(userF), 30e18, "Avalanche.F: initial balance");
        assertEq(bridgedTokenAvalanche.balanceOf(userA), 70e18, "Avalanche.A: initial balance");

        vm.prank(avalanche.multisig);
        bridgedTokenAvalanche.setPaused(address(bridgedTokenAvalanche), true);

        // ----------- Tests
        _testSendToAvalancheOnPause(userF, 1e18, userA, true); // forbidden
        _testSendToAvalancheOnPause(userA, 1e18, userF, true); // allowed
        _testSendToSonicOnPause(userF, 1e18, userA, true); // forbidden
        _testSendToSonicOnPause(userA, 1e18, userF, true); // allowed
    }

    //endregion ------------------------------------- Test: Send from Sonic to Avalanche and back

    //region ------------------------------------- Test implementation
    function _testSendToAvalancheAndCheck(address sender, uint sendAmount, uint balance0, address receiver) internal {
        uint shapshot = vm.snapshotState();

        Results memory r = _testSendFromSonicToBridged(sender, sendAmount, balance0, receiver, avalanche);

        assertEq(r.srcBefore.balanceSenderSTBL, balance0, "sender's initial STBL balance");
        assertEq(r.srcBefore.balanceContractSTBL, 0, "no tokens in adapter initially");
        assertEq(r.srcAfter.balanceSenderSTBL, balance0 - sendAmount, "sender's final STBL balance");
        assertEq(r.srcAfter.balanceContractSTBL, sendAmount, "all tokens are in adapter");

        assertEq(r.targetBefore.balanceReceiverSTBL, 0, "receiver has no tokens on avalanche initially");
        assertEq(r.targetAfter.balanceReceiverSTBL, sendAmount, "receiver has received expected amount");

        assertEq(r.srcBefore.balanceSenderEther, r.srcAfter.balanceSenderEther + r.nativeFee, "expected fee");
        vm.revertToState(shapshot);
    }

    /// @notice Sends tokens from Sonic to Target chain
    function _testSendFromSonicToBridged(
        address sender,
        uint sendAmount,
        uint balance0,
        address receiver,
        ChainConfig memory target
    ) internal returns (Results memory dest) {
        vm.selectFork(sonic.fork);

        // ------------------- Prepare user tokens
        deal(sender, 1 ether); // to pay fees
        deal(SonicConstantsLib.TOKEN_STBL, sender, balance0);

        vm.prank(sender);
        IERC20(SonicConstantsLib.TOKEN_STBL).approve(address(adapter), sendAmount);

        // ------------------- Prepare send options
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT, 0);

        SendParam memory sendParam = SendParam({
            dstEid: target.endpointId,
            to: bytes32(uint(uint160(receiver))),
            amountLD: sendAmount,
            minAmountLD: sendAmount,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory msgFee = adapter.quoteSend(sendParam, false);
        // console.log("Quoted native fee:", msgFee.nativeFee);

        dest.srcBefore = _getBalancesSonic(sender, receiver);

        // ------------------- Send
        vm.recordLogs();

        vm.prank(sender);
        adapter.send{value: msgFee.nativeFee}(sendParam, msgFee, sender);
        bytes memory message = _extractSendMessage(vm.getRecordedLogs());

        // ------------------ Target: simulate message reception
        vm.selectFork(target.fork);
        dest.targetBefore = _getBalancesBridged(sender, receiver, target);

        Origin memory origin = Origin({
            srcEid: SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            sender: bytes32(uint(uint160(address(adapter)))),
            nonce: 1
        });

        {
            uint gasBefore = gasleft();
            vm.prank(target.endpoint);
            IOAppReceiver(target.oapp)
                .lzReceive(
                    origin,
                    bytes32(0), // guid: actual value doesn't matter
                    message,
                    address(0), // executor
                    "" // extraData
                );
            assertLt(gasBefore - gasleft(), GAS_LIMIT, "gas limit exceeded"); // ~60 ths
            // console.log("gasBefore - gasleft()", gasBefore - gasleft());
        }

        dest.targetAfter = _getBalancesBridged(sender, receiver, target);
        vm.selectFork(sonic.fork);
        dest.srcAfter = _getBalancesSonic(sender, receiver);

        dest.nativeFee = msgFee.nativeFee;

        return dest;
    }

    /// @notice Sends tokens from a target chain to Sonic
    function _testSendFromBridgedToSonic(
        address sender,
        uint sendAmount,
        address receiver,
        ChainConfig memory target
    ) internal returns (Results memory dest) {
        vm.selectFork(target.fork);

        // ------------------- Prepare user tokens
        deal(sender, 1 ether); // to pay fees

        vm.prank(sender);
        IERC20(target.oapp).approve(target.oapp, sendAmount);

        // ------------------- Prepare send options
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(2_000_000, 0);

        SendParam memory sendParam = SendParam({
            dstEid: SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            to: bytes32(uint(uint160(receiver))),
            amountLD: sendAmount,
            minAmountLD: sendAmount,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory msgFee = IOFT(target.oapp).quoteSend(sendParam, false);

        dest.srcBefore = _getBalancesBridged(sender, receiver, target);

        // ------------------- Send
        vm.recordLogs();

        vm.prank(sender);
        IOFT(target.oapp).send{value: msgFee.nativeFee}(sendParam, msgFee, sender);
        bytes memory message = _extractSendMessage(vm.getRecordedLogs());

        // ------------------ Sonic: simulate message reception
        vm.selectFork(sonic.fork);
        dest.targetBefore = _getBalancesSonic(sender, receiver);

        Origin memory origin =
            Origin({srcEid: target.endpointId, sender: bytes32(uint(uint160(target.oapp))), nonce: 1});

        vm.prank(SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT);
        adapter.lzReceive(
            origin,
            bytes32(0), // guid: actual value doesn't matter
            message,
            address(0), // executor
            "" // extraData
        );

        dest.targetAfter = _getBalancesSonic(sender, receiver);
        vm.selectFork(target.fork);
        dest.srcAfter = _getBalancesBridged(sender, receiver, target);

        dest.nativeFee = msgFee.nativeFee;

        return dest;
    }

    /// @notice Sends tokens from src to target chain
    function _testSendFromBridgedToBridged(
        address sender,
        uint sendAmount,
        address receiver,
        ChainConfig memory src,
        ChainConfig memory target
    ) internal returns (Results memory dest) {
        vm.selectFork(src.fork);

        // ------------------- Prepare user tokens
        deal(sender, 1 ether); // to pay fees
        // assume that the sender has enough balance

        vm.prank(sender);
        IERC20(src.oapp).approve(address(adapter), sendAmount);

        // ------------------- Prepare send options
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT, 0);

        SendParam memory sendParam = SendParam({
            dstEid: target.endpointId,
            to: bytes32(uint(uint160(receiver))),
            amountLD: sendAmount,
            minAmountLD: sendAmount,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory msgFee = IOFT(src.oapp).quoteSend(sendParam, false);
        // console.log("Quoted native fee:", msgFee.nativeFee);

        dest.srcBefore = _getBalancesBridged(sender, receiver, src);

        // ------------------- Send
        vm.recordLogs();

        vm.prank(sender);
        IOFT(src.oapp).send{value: msgFee.nativeFee}(sendParam, msgFee, sender);
        bytes memory message = _extractSendMessage(vm.getRecordedLogs());

        // ------------------ Target: simulate message reception
        vm.selectFork(target.fork);
        dest.targetBefore = _getBalancesBridged(sender, receiver, target);

        Origin memory origin = Origin({srcEid: src.endpointId, sender: bytes32(uint(uint160(src.oapp))), nonce: 1});

        {
            uint gasBefore = gasleft();
            vm.prank(target.endpoint);
            IOAppReceiver(target.oapp)
                .lzReceive(
                    origin,
                    bytes32(0), // guid: actual value doesn't matter
                    message,
                    address(0), // executor
                    "" // extraData
                );
            assertLt(gasBefore - gasleft(), GAS_LIMIT, "gas limit exceeded");
            // console.log("gasBefore - gasleft()", gasBefore - gasleft());
        }

        dest.targetAfter = _getBalancesBridged(sender, receiver, target);
        vm.selectFork(src.fork);
        dest.srcAfter = _getBalancesBridged(sender, receiver, src);

        dest.nativeFee = msgFee.nativeFee;

        return dest;
    }

    function _testSendToAvalancheOnPause(
        address sender,
        uint sendAmount,
        address receiver,
        bool expectSuccess
    ) internal {
        vm.selectFork(sonic.fork);
        uint snapshot = vm.snapshotState();

        deal(sender, 1 ether); // to pay fees

        vm.prank(sender);
        IERC20(SonicConstantsLib.TOKEN_STBL).approve(address(adapter), sendAmount);

        SendParam memory sendParam = SendParam({
            dstEid: AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            to: bytes32(uint(uint160(receiver))),
            amountLD: sendAmount,
            minAmountLD: sendAmount,
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(2_000_000, 0),
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory msgFee = adapter.quoteSend(sendParam, false);

        // ------------------- Send
        vm.prank(sender);
        if (!expectSuccess) {
            vm.expectRevert(IOFTPausable.Paused.selector);
        }
        adapter.send{value: msgFee.nativeFee}(sendParam, msgFee, sender);

        vm.revertToState(snapshot);
    }

    function _testSendToSonicOnPause(address sender, uint sendAmount, address receiver, bool expectSuccess) internal {
        vm.selectFork(avalanche.fork);
        uint snapshot = vm.snapshotState();

        deal(sender, 1 ether); // to pay fees

        vm.prank(sender);
        bridgedTokenAvalanche.approve(address(bridgedTokenAvalanche), sendAmount);

        SendParam memory sendParam = SendParam({
            dstEid: SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            to: bytes32(uint(uint160(receiver))),
            amountLD: sendAmount,
            minAmountLD: sendAmount,
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(2_000_000, 0),
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory msgFee = bridgedTokenAvalanche.quoteSend(sendParam, false);

        vm.prank(sender);
        if (!expectSuccess) {
            vm.expectRevert(IOFTPausable.Paused.selector);
        }
        bridgedTokenAvalanche.send{value: msgFee.nativeFee}(sendParam, msgFee, sender);

        vm.revertToState(snapshot);
    }

    //endregion ------------------------------------- Test implementation

    //region ------------------------------------- Internal logic
    function _getBalancesSonic(address sender, address receiver) internal view returns (ChainResults memory res) {
        res.balanceSenderSTBL = IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(sender);
        res.balanceContractSTBL = IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(address(adapter));
        res.balanceReceiverSTBL = IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(receiver);
        res.totalSupplySTBL = IERC20(SonicConstantsLib.TOKEN_STBL).totalSupply();
        res.balanceSenderEther = sender.balance;
        //        console.log("Sonic.balanceSenderSTBL", res.balanceSenderSTBL);
        //        console.log("Sonic.balanceContractSTBL", res.balanceContractSTBL);
        //        console.log("Sonic.balanceReceiverSTBL", res.balanceReceiverSTBL);
        //        console.log("Sonic.totalSupplySTBL", res.totalSupplySTBL);

        return res;
    }

    function _getBalancesBridged(
        address sender,
        address receiver,
        ChainConfig memory target
    ) internal view returns (ChainResults memory res) {
        res.balanceSenderSTBL = IERC20(target.oapp).balanceOf(sender);
        res.balanceContractSTBL = IERC20(target.oapp).balanceOf(address(target.oapp));
        res.balanceReceiverSTBL = IERC20(target.oapp).balanceOf(receiver);
        res.totalSupplySTBL = IERC20(target.oapp).totalSupply();
        res.balanceSenderEther = sender.balance;
        //        console.log("Avalanche.balanceSenderSTBL", res.balanceSenderSTBL);
        //        console.log("Avalanche.balanceContractSTBL", res.balanceContractSTBL);
        //        console.log("Avalanche.balanceReceiverSTBL", res.balanceReceiverSTBL);
        //        console.log("Avalanche.totalSupplySTBL", res.totalSupplySTBL);

        return res;
    }

    function _showResults(ChainResults memory res) internal pure {
        console.log("balanceSenderSTBL:", res.balanceSenderSTBL);
        console.log("balanceContractSTBL:", res.balanceContractSTBL);
        console.log("balanceReceiverSTBL:", res.balanceReceiverSTBL);
        console.log("totalSupplySTBL:", res.totalSupplySTBL);
    }

    function setupSTBLBridged(ChainConfig memory chain) internal returns (address) {
        vm.selectFork(chain.fork);

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new BridgedToken(chain.endpoint)));
        BridgedToken bridgedStbl = BridgedToken(address(proxy));
        bridgedStbl.initialize(address(chain.platform), "Stability STBL", "STBL");

        assertEq(bridgedStbl.owner(), chain.multisig, "multisig is owner");

        return address(bridgedStbl);
    }

    function setupStabilityOFTAdapterOnSonic() internal returns (address) {
        vm.selectFork(sonic.fork);

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new StabilityOFTAdapter(SonicConstantsLib.TOKEN_STBL, sonic.endpoint)));
        StabilityOFTAdapter stblOFTAdapter = StabilityOFTAdapter(address(proxy));
        stblOFTAdapter.initialize(address(sonic.platform));

        assertEq(stblOFTAdapter.owner(), sonic.multisig, "sonic.multisig is owner");

        return address(stblOFTAdapter);
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
                    dst.endpointId, // Source chain EID
                    src.receiveLib, // ReceiveUln302 address
                    GRACE_PERIOD // Grace period for library switch
                );
        }
    }

    function _setPeers(ChainConfig memory src, ChainConfig memory dst) internal {
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
        ChainConfig memory src,
        ChainConfig memory dst,
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
            maxMessageSize: 40, // max bytes per cross-chain message
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
        ChainConfig memory src,
        ChainConfig memory dst,
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
    function _extractSendMessage(Vm.Log[] memory logs) internal pure returns (bytes memory message) {
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
