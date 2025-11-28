// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {AvalancheConstantsLib} from "../../chains/avalanche/AvalancheConstantsLib.sol";
import {BridgeTestLib} from "./libs/BridgeTestLib.sol";
import {BridgedToken} from "../../src/tokenomics/BridgedToken.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOAppReceiver} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";
import {IOFTPausable} from "../../src/interfaces/IOFTPausable.sol";
import {IOFT} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";
import {PacketV1Codec} from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import {OFTMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import {SendParam} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
// import {InboundPacket, PacketDecoder} from "@layerzerolabs/lz-evm-protocol-v2/../oapp/contracts/precrime/libs/Packet.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {StabilityOFTAdapter} from "../../src/tokenomics/StabilityOFTAdapter.sol";
import {console, Test} from "forge-std/Test.sol";

contract BridgedTokenTest is Test {
    using OptionsBuilder for bytes;
    using PacketV1Codec for bytes;
    using SafeERC20 for IERC20;

    //region ------------------------------------- Constants, data types, variables
    uint private constant SONIC_FORK_BLOCK = 52228979; // Oct-28-2025 01:14:21 PM +UTC
    uint private constant AVALANCHE_FORK_BLOCK = 71037861; // Oct-28-2025 13:17:17 UTC
    uint private constant PLASMA_FORK_BLOCK = 5398928; // Nov-5-2025 07:38:59 UTC

    /// @dev Gas limit for executor lzReceive calls
    /// 2 mln => fee = 0.78 S
    /// 100_000 => fee = 0.36 S
    uint128 private constant GAS_LIMIT = 60_000;

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

    BridgeTestLib.ChainConfig internal sonic;
    BridgeTestLib.ChainConfig internal avalanche;
    BridgeTestLib.ChainConfig internal plasma;
    //endregion ------------------------------------- Constants, data types, variables

    constructor() {
        {
            uint forkSonic = vm.createFork(vm.envString("SONIC_RPC_URL"), SONIC_FORK_BLOCK);
            uint forkAvalanche = vm.createFork(vm.envString("AVALANCHE_RPC_URL"), AVALANCHE_FORK_BLOCK);
            uint forkPlasma = vm.createFork(vm.envString("PLASMA_RPC_URL"), PLASMA_FORK_BLOCK);

            sonic = BridgeTestLib.createConfigSonic(vm, forkSonic);
            avalanche = BridgeTestLib.createConfigAvalanche(vm, forkAvalanche);
            plasma = BridgeTestLib.createConfigPlasma(vm, forkPlasma);
        }

        // ------------------- Create adapter and bridged token
        adapter = StabilityOFTAdapter(BridgeTestLib.setupStabilityOFTAdapterOnSonic(vm, sonic));
        bridgedTokenAvalanche = BridgedToken(BridgeTestLib.setupSTBLBridged(vm, avalanche));
        bridgedTokenPlasma = BridgedToken(BridgeTestLib.setupSTBLBridged(vm, plasma));

        vm.selectFork(avalanche.fork);
        assertEq(bridgedTokenAvalanche.owner(), avalanche.multisig, "multisig is owner");
        vm.selectFork(plasma.fork);
        assertEq(bridgedTokenPlasma.owner(), plasma.multisig, "multisig is owner");
        vm.selectFork(sonic.fork);
        assertEq(adapter.owner(), sonic.multisig, "sonic.multisig is owner");


        sonic.oapp = address(adapter);
        avalanche.oapp = address(bridgedTokenAvalanche);
        plasma.oapp = address(bridgedTokenPlasma);

        // ------------------- Set up Sonic:Avalanche
        BridgeTestLib.setUpSonicAvalanche(vm, sonic, avalanche);

        // ------------------- Set up Sonic:Plasma
        BridgeTestLib.setUpSonicPlasma(vm, sonic, plasma);

        // ------------------- Set up Avalanche:Plasma
        BridgeTestLib.setUpAvalanchePlasma(vm, avalanche, plasma);

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

        BridgeTestLib._getConfig(
            vm,
            avalanche.fork,
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            address(bridgedTokenAvalanche),
            AvalancheConstantsLib.LAYER_ZERO_V2_RECEIVE_ULN_302,
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            BridgeTestLib.CONFIG_TYPE_ULN
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
        assertEq(bridgedTokenAvalanche.sharedDecimals(), BridgeTestLib.SHARED_DECIMALS, "BridgedToken - shared decimals");
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
        assertEq(adapter.sharedDecimals(), BridgeTestLib.SHARED_DECIMALS, "StabilityOFTAdapter - shared decimals");
    }

    function testConfigStabilityOFTAdapter() internal {
        BridgeTestLib._getConfig(
            vm,
            sonic.fork,
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            address(adapter),
            SonicConstantsLib.LAYER_ZERO_V2_SEND_ULN_302,
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            BridgeTestLib.CONFIG_TYPE_EXECUTOR
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
        BridgeTestLib.ChainConfig memory target
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
        bytes memory message = BridgeTestLib._extractSendMessage(vm.getRecordedLogs());

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
        BridgeTestLib.ChainConfig memory target
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
        bytes memory message = BridgeTestLib._extractSendMessage(vm.getRecordedLogs());

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
        BridgeTestLib.ChainConfig memory src,
        BridgeTestLib.ChainConfig memory target
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
        bytes memory message = BridgeTestLib._extractSendMessage(vm.getRecordedLogs());

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
        BridgeTestLib.ChainConfig memory target
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

    //endregion ------------------------------------- Internal logic
}