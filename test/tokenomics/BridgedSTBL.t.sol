// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console, Test, Vm} from "forge-std/Test.sol";
import {BridgedSTBL} from "../../src/tokenomics/BridgedSTBL.sol";
import {STBLOFTAdapter} from "../../src/tokenomics/STBLOFTAdapter.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IBridgedSTBL} from "../../src/interfaces/IBridgedSTBL.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {AvalancheConstantsLib} from "../../chains/avalanche/AvalancheConstantsLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
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

contract BridgedSTBLTest is Test {
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

    STBLOFTAdapter internal adapter;
    BridgedSTBL internal bridgedToken;

    struct ChainResutls {
        uint balanceSenderSTBL;
        uint balanceContractSTBL;
        uint balanceReceiverSTBL;
        uint totalSupplySTBL;
        uint balanceSenderEther;
    }

    struct Results {
        ChainResutls sonicBefore;
        ChainResutls avalancheBefore;
        ChainResutls sonicAfter;
        ChainResutls avalancheAfter;
        uint nativeFee;
    }

    struct TestCaseSendToAvalanche {
        address sender;
        uint sendAmount;
        uint initialBalance;
        address receiver;
    }

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

        // ------------------- Set up layer zero on both chains
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

    //region ------------------------------------- Unit tests for bridgetSTBL
    function testConfigBridgetSTBL() public {
        //        _getConfig(
        //            forkAvalanche,
        //            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT,
        //            address(bridgedToken),
        //            AvalancheConstantsLib.LAYER_ZERO_V2_RECEIVE_ULN_302,
        //            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
        //            CONFIG_TYPE_EXECUTOR
        //        );

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

    function testBridgedStblPause() public {
        vm.selectFork(forkAvalanche);

        assertEq(bridgedToken.paused(address(this)), false);

        vm.prank(multisigAvalanche);
        bridgedToken.setPaused(address(this), true);
        assertEq(bridgedToken.paused(address(this)), true);

        vm.prank(address(this));
        vm.expectRevert(IControllable.NotOperator.selector);
        bridgedToken.setPaused(address(this), true);

        vm.prank(multisigAvalanche);
        bridgedToken.setPaused(address(this), false);
        assertEq(bridgedToken.paused(address(this)), false);
    }

    //endregion ------------------------------------- Unit tests for bridgetSTBL

    //region ------------------------------------- Unit tests for STBLOFTAdapter
    function testViewSTBLOFTAdapter() public {
        vm.selectFork(forkSonic);

        assertEq(adapter.owner(), multisigSonic);
    }

    function testConfigSTBLOFTAdapter() public {
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
    }

    function testAdapterPause() public {
        vm.selectFork(forkSonic);

        assertEq(adapter.paused(address(this)), false);

        vm.prank(multisigSonic);
        adapter.setPaused(address(this), true);
        assertEq(adapter.paused(address(this)), true);

        vm.prank(address(this));
        vm.expectRevert(IControllable.NotOperator.selector);
        adapter.setPaused(address(this), true);

        vm.prank(multisigSonic);
        adapter.setPaused(address(this), false);
        assertEq(adapter.paused(address(this)), false);
    }

    //endregion ------------------------------------- Unit tests for STBLOFTAdapter

    //region ------------------------------------- Test: Send from Sonic to Avalanche
    function fixtureDataSA() public returns (TestCaseSendToAvalanche[] memory) {
        TestCaseSendToAvalanche[] memory tests = new TestCaseSendToAvalanche[](3);

        tests[0] = TestCaseSendToAvalanche({
            sender: address(this), sendAmount: 1e18, initialBalance: 800e18, receiver: address(this)
        });

        tests[1] = TestCaseSendToAvalanche({
            sender: address(this), sendAmount: 799_000e18, initialBalance: 800_000e18, receiver: address(this)
        });

        tests[2] = TestCaseSendToAvalanche({
            sender: address(this), sendAmount: 799_000e18, initialBalance: 800_000e18, receiver: makeAddr("111")
        });

        return tests;
    }

    function tableDataSATest(TestCaseSendToAvalanche memory dataSA) public {
        _testSendToAvalancheAndCheck(dataSA.sender, dataSA.sendAmount, dataSA.initialBalance, dataSA.receiver);
    }
    //endregion ------------------------------------- Test: Send from Sonic to Avalanche

    //region ------------------------------------- Test: Send from Sonic to Avalanche and back

    function testSendToAvalancheAndBack() public {
        // ------------- There are 4 users: A, B, C, D
        address userA = makeAddr("A");
        address userB = makeAddr("B");
        address userC = makeAddr("C");
        address userD = makeAddr("D");

        // ------------- Sonic.A => Avalanche.B
        Results memory r1 = _testSendToAvalanche(userA, 157e18, 357e18, userB);

        assertEq(r1.sonicAfter.balanceSenderSTBL, 357e18 - 157e18, "A balance 1");
        assertEq(r1.avalancheAfter.balanceReceiverSTBL, 157e18, "B balance 1");

        // ------------- Avalanche.B => Avalanche.C
        vm.selectFork(forkAvalanche);
        vm.prank(userB);
        IERC20(bridgedToken).safeTransfer(userC, 100e18);

        assertEq(bridgedToken.balanceOf(userB), 57e18, "B balance 2");
        assertEq(bridgedToken.balanceOf(userC), 100e18, "C balance 2");

        // ------------- Avalanche.C => Sonic.D
        Results memory r2 = _testSendToSonic(userC, 80e18, userD);

        assertEq(r2.avalancheAfter.balanceSenderSTBL, 20e18, "C balance 3");
        assertEq(r2.sonicAfter.balanceReceiverSTBL, 80e18, "D balance 3");

        assertEq(r2.avalancheAfter.totalSupplySTBL, 57e18 + 20e18, "total supply after all transfers: b + c");
        assertEq(r2.sonicAfter.totalSupplySTBL, r1.sonicBefore.totalSupplySTBL, "total supply of STBL wasn't changed");
    }

    function testUserPausedOnSonic() public {
        address userF = makeAddr("A");
        address userA = makeAddr("D");

        // ------------- Prepare
        _testSendToAvalanche(userF, 100e18, 500e18, userF);

        vm.selectFork(forkSonic);
        deal(SonicConstantsLib.TOKEN_STBL, userA, 300e18);

        assertEq(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(userF), 400e18, "Sonic.F: initial balance");
        assertEq(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(userA), 300e18, "Sonic.A: initial balance");

        vm.prank(multisigSonic);
        adapter.setPaused(userF, true);

        vm.selectFork(forkAvalanche);
        vm.prank(userF);
        IERC20(bridgedToken).safeTransfer(userA, 70e18);

        assertEq(bridgedToken.balanceOf(userF), 30e18, "Avalanche.F: initial balance");
        assertEq(bridgedToken.balanceOf(userA), 70e18, "Avalanche.A: initial balance");

        // ----------- Tests
        _testSendToAvalancheOnPause(userF, 1e18, userA, false); // forbidden
        _testSendToAvalancheOnPause(userA, 1e18, userF, true); // allowed
        _testSendToSonicOnPause(userF, 1e18, userA, false); // allowed
        _testSendToSonicOnPause(userA, 1e18, userF, true); // allowed
    }

    function testUserPausedOnAvalanche() public {
        address userF = makeAddr("A");
        address userA = makeAddr("D");

        _testSendToAvalanche(userF, 100e18, 500e18, userF);

        vm.selectFork(forkSonic);
        deal(SonicConstantsLib.TOKEN_STBL, userA, 300e18);

        assertEq(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(userF), 400e18, "Sonic.F: initial balance");
        assertEq(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(userA), 300e18, "Sonic.A: initial balance");

        vm.selectFork(forkAvalanche);
        vm.prank(userF);
        IERC20(bridgedToken).safeTransfer(userA, 70e18);

        assertEq(bridgedToken.balanceOf(userF), 30e18, "Avalanche.F: initial balance");
        assertEq(bridgedToken.balanceOf(userA), 70e18, "Avalanche.A: initial balance");

        vm.prank(multisigAvalanche);
        bridgedToken.setPaused(userF, true);

        // ----------- Tests
        _testSendToAvalancheOnPause(userF, 1e18, userA, true); // allowed
        _testSendToAvalancheOnPause(userA, 1e18, userF, true); // allowed
        _testSendToSonicOnPause(userF, 1e18, userA, false); // forbidden
        _testSendToSonicOnPause(userA, 1e18, userF, true); // allowed
    }

    function testUserPausedOnBothChains() public {
        address userF = makeAddr("A");
        address userA = makeAddr("D");

        // ------------- Prepare
        _testSendToAvalanche(userF, 100e18, 500e18, userF);

        vm.selectFork(forkSonic);
        deal(SonicConstantsLib.TOKEN_STBL, userA, 300e18);

        assertEq(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(userF), 400e18, "Sonic.F: initial balance");
        assertEq(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(userA), 300e18, "Sonic.A: initial balance");

        vm.prank(multisigSonic);
        adapter.setPaused(userF, true);

        vm.selectFork(forkAvalanche);
        vm.prank(userF);
        IERC20(bridgedToken).safeTransfer(userA, 70e18);

        assertEq(bridgedToken.balanceOf(userF), 30e18, "Avalanche.F: initial balance");
        assertEq(bridgedToken.balanceOf(userA), 70e18, "Avalanche.A: initial balance");

        vm.prank(multisigAvalanche);
        bridgedToken.setPaused(userF, true);

        // ----------- Tests
        _testSendToAvalancheOnPause(userF, 1e18, userA, false); // forbidden
        _testSendToAvalancheOnPause(userA, 1e18, userF, true); // allowed
        _testSendToSonicOnPause(userF, 1e18, userA, false); // forbidden
        _testSendToSonicOnPause(userA, 1e18, userF, true); // allowed
    }

    //endregion ------------------------------------- Test: Send from Sonic to Avalanche and back

    //region ------------------------------------- Test implementation
    function _testSendToAvalancheAndCheck(address sender, uint sendAmount, uint balance0, address receiver) internal {
        uint shapshot = vm.snapshotState();

        Results memory r = _testSendToAvalanche(sender, sendAmount, balance0, receiver);

        assertEq(r.sonicBefore.balanceSenderSTBL, balance0, "sender's initial STBL balance");
        assertEq(r.sonicBefore.balanceContractSTBL, 0, "no tokens in adapter initially");
        assertEq(r.sonicAfter.balanceSenderSTBL, balance0 - sendAmount, "sender's final STBL balance");
        assertEq(r.sonicAfter.balanceContractSTBL, sendAmount, "all tokens are in adapter");

        assertEq(r.avalancheBefore.balanceReceiverSTBL, 0, "receiver has no tokens on avalanche initially");
        assertEq(r.avalancheAfter.balanceReceiverSTBL, sendAmount, "receiver has received expected amount");

        assertEq(r.sonicBefore.balanceSenderEther, r.sonicAfter.balanceSenderEther + r.nativeFee, "expected fee");
        vm.revertToState(shapshot);
    }

    /// @notice Sends tokens from Sonic to Avalanche
    function _testSendToAvalanche(
        address sender,
        uint sendAmount,
        uint balance0,
        address receiver
    ) internal returns (Results memory dest) {
        vm.selectFork(forkSonic);

        // ------------------- Prepare user tokens
        deal(sender, 1 ether); // to pay fees
        deal(SonicConstantsLib.TOKEN_STBL, sender, balance0);

        vm.prank(sender);
        IERC20(SonicConstantsLib.TOKEN_STBL).approve(address(adapter), sendAmount);

        // ------------------- Prepare send options
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(2_000_000, 0);

        SendParam memory sendParam = SendParam({
            dstEid: AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            to: bytes32(uint(uint160(receiver))),
            amountLD: sendAmount,
            minAmountLD: sendAmount,
            extraOptions: options,
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory msgFee = adapter.quoteSend(sendParam, false);

        dest.sonicBefore = _getBalancesSonic(sender, receiver);

        // ------------------- Send
        vm.recordLogs();

        vm.prank(sender);
        adapter.send{value: msgFee.nativeFee}(sendParam, msgFee, sender);
        bytes memory message = _extractSendMessage();

        // ------------------ Avalanche: simulate message reception
        vm.selectFork(forkAvalanche);
        dest.avalancheBefore = _getBalancesAvalanche(sender, receiver);

        Origin memory origin = Origin({
            srcEid: SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            sender: bytes32(uint(uint160(address(adapter)))),
            nonce: 1
        });

        vm.prank(AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT);
        bridgedToken.lzReceive(
            origin,
            bytes32(0), // guid: actual value doesn't matter
            message,
            address(0), // executor
            "" // extraData
        );

        dest.avalancheAfter = _getBalancesAvalanche(sender, receiver);
        vm.selectFork(forkSonic);
        dest.sonicAfter = _getBalancesSonic(sender, receiver);

        dest.nativeFee = msgFee.nativeFee;

        return dest;
    }

    /// @notice Sends tokens from Avalanche to Sonic
    function _testSendToSonic(
        address sender,
        uint sendAmount,
        address receiver
    ) internal returns (Results memory dest) {
        vm.selectFork(forkAvalanche);

        // ------------------- Prepare user tokens
        deal(sender, 1 ether); // to pay fees

        vm.prank(sender);
        bridgedToken.approve(address(bridgedToken), sendAmount);

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
        MessagingFee memory msgFee = bridgedToken.quoteSend(sendParam, false);

        dest.avalancheBefore = _getBalancesAvalanche(sender, receiver);

        // ------------------- Send
        vm.recordLogs();

        vm.prank(sender);
        bridgedToken.send{value: msgFee.nativeFee}(sendParam, msgFee, sender);
        bytes memory message = _extractSendMessage();

        // ------------------ Sonic: simulate message reception
        vm.selectFork(forkSonic);
        dest.sonicBefore = _getBalancesSonic(sender, receiver);

        Origin memory origin = Origin({
            srcEid: AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            sender: bytes32(uint(uint160(address(bridgedToken)))),
            nonce: 1
        });

        vm.prank(SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT);
        adapter.lzReceive(
            origin,
            bytes32(0), // guid: actual value doesn't matter
            message,
            address(0), // executor
            "" // extraData
        );

        dest.sonicAfter = _getBalancesSonic(sender, receiver);
        vm.selectFork(forkAvalanche);
        dest.avalancheAfter = _getBalancesAvalanche(sender, receiver);

        dest.nativeFee = msgFee.nativeFee;

        return dest;
    }

    function _testSendToAvalancheOnPause(
        address sender,
        uint sendAmount,
        address receiver,
        bool expectSuccess
    ) internal {
        vm.selectFork(forkSonic);
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
            vm.expectRevert(IBridgedSTBL.Paused.selector);
        }
        adapter.send{value: msgFee.nativeFee}(sendParam, msgFee, sender);

        vm.revertToState(snapshot);
    }

    function _testSendToSonicOnPause(address sender, uint sendAmount, address receiver, bool expectSuccess) internal {
        vm.selectFork(forkAvalanche);
        uint snapshot = vm.snapshotState();

        deal(sender, 1 ether); // to pay fees

        vm.prank(sender);
        bridgedToken.approve(address(bridgedToken), sendAmount);

        SendParam memory sendParam = SendParam({
            dstEid: SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            to: bytes32(uint(uint160(receiver))),
            amountLD: sendAmount,
            minAmountLD: sendAmount,
            extraOptions: OptionsBuilder.newOptions().addExecutorLzReceiveOption(2_000_000, 0),
            composeMsg: "",
            oftCmd: ""
        });
        MessagingFee memory msgFee = bridgedToken.quoteSend(sendParam, false);

        vm.prank(sender);
        if (!expectSuccess) {
            vm.expectRevert(IBridgedSTBL.Paused.selector);
        }
        bridgedToken.send{value: msgFee.nativeFee}(sendParam, msgFee, sender);

        vm.revertToState(snapshot);
    }

    //endregion ------------------------------------- Test implementation

    //region ------------------------------------- Internal logic
    function _getBalancesSonic(address sender, address receiver) internal view returns (ChainResutls memory res) {
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

    function _getBalancesAvalanche(address sender, address receiver) internal view returns (ChainResutls memory res) {
        res.balanceSenderSTBL = IERC20(bridgedToken).balanceOf(sender);
        res.balanceContractSTBL = IERC20(bridgedToken).balanceOf(address(bridgedToken));
        res.balanceReceiverSTBL = IERC20(bridgedToken).balanceOf(receiver);
        res.totalSupplySTBL = IERC20(bridgedToken).totalSupply();
        res.balanceSenderEther = sender.balance;
        //        console.log("Avalanche.balanceSenderSTBL", res.balanceSenderSTBL);
        //        console.log("Avalanche.balanceContractSTBL", res.balanceContractSTBL);
        //        console.log("Avalanche.balanceReceiverSTBL", res.balanceReceiverSTBL);
        //        console.log("Avalanche.totalSupplySTBL", res.totalSupplySTBL);

        return res;
    }

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
        proxy.initProxy(
            address(new STBLOFTAdapter(SonicConstantsLib.TOKEN_STBL, SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT))
        );
        STBLOFTAdapter stblOFTAdapter = STBLOFTAdapter(address(proxy));
        stblOFTAdapter.initialize(address(SonicConstantsLib.PLATFORM));

        assertEq(stblOFTAdapter.owner(), multisigSonic, "multisigSonic is owner");

        return address(stblOFTAdapter);
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
        adapter.setPeer(AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, bytes32(uint(uint160(address(bridgedToken)))));

        // ------------------- Avalanche: set up peer connection
        vm.selectFork(forkAvalanche);

        vm.prank(multisigAvalanche);
        bridgedToken.setPeer(SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID, bytes32(uint(uint160(address(adapter)))));
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

        console.logBytes(message);
        return message;
    }
    //endregion ------------------------------------- Internal logic
}
