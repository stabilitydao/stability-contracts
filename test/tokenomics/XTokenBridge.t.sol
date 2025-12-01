// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {XSTBL} from "../../src/tokenomics/XSTBL.sol";
import {BridgeTestLib} from "./libs/BridgeTestLib.sol";
import {console, Test} from "forge-std/Test.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";
import {XTokenBridge} from "../../src/tokenomics/XTokenBridge.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {IXSTBL} from "../../src/interfaces/IXSTBL.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IOFTPausable} from "../../src/interfaces/IOFTPausable.sol";
import {IXTokenBridge} from "../../src/interfaces/IXTokenBridge.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StabilityOFTAdapter} from "../../src/tokenomics/StabilityOFTAdapter.sol";
import {BridgedToken} from "../../src/tokenomics/BridgedToken.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {IOAppReceiver} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";
import {IOAppComposer} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";
import {MockXToken} from "../../src/test/MockXToken.sol";
import {OFTComposeMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";

contract XTokenBridgeTest is Test {
    using OptionsBuilder for bytes;
    using SafeERC20 for IERC20;

    //region ------------------------------------- Constants, data types, variables
    uint private constant SONIC_FORK_BLOCK = 52228979; // Oct-28-2025 01:14:21 PM +UTC
    uint private constant AVALANCHE_FORK_BLOCK = 71037861; // Oct-28-2025 13:17:17 UTC
    uint private constant PLASMA_FORK_BLOCK = 5398928; // Nov-5-2025 07:38:59 UTC

    /// @dev Gas limit for executor lzReceive calls
    uint128 private constant GAS_LIMIT_LZRECEIVE = 100_000;
    /// @dev Gas limit for executor lzCompose calls
    uint128 private constant GAS_LIMIT_LZCOMPOSE = 150_000;

    StabilityOFTAdapter internal adapter;
    BridgedToken internal bridgedTokenAvalanche;
    BridgedToken internal bridgedTokenPlasma;

    BridgeTestLib.ChainConfig internal sonic;
    BridgeTestLib.ChainConfig internal avalanche;
    BridgeTestLib.ChainConfig internal plasma;

    struct ChainResults {
        uint balanceUserSTBL;
        uint balanceUserXSTBL;
        uint balanceOappSTBL;
        uint balanceXTokenSTBL;
        uint balanceUserEther;
        uint balanceXTokenBridgeSTBL;
    }

    struct Results {
        ChainResults srcBefore;
        ChainResults targetBefore;
        ChainResults srcAfter;
        ChainResults targetAfter;
        uint nativeFee;
    }

    //endregion ------------------------------------- Constants, data types, variables

    //region ------------------------------------- Constructor
    constructor() {
        {
            uint forkSonic = vm.createFork(vm.envString("SONIC_RPC_URL"), SONIC_FORK_BLOCK);
            uint forkAvalanche = vm.createFork(vm.envString("AVALANCHE_RPC_URL"), AVALANCHE_FORK_BLOCK);
            uint forkPlasma = vm.createFork(vm.envString("PLASMA_RPC_URL"), PLASMA_FORK_BLOCK);

            sonic = BridgeTestLib.createConfigSonic(vm, forkSonic);
            avalanche = BridgeTestLib.createConfigAvalanche(vm, forkAvalanche);
            plasma = BridgeTestLib.createConfigPlasma(vm, forkPlasma);
        }

        // ------------------- Create bridge for STBL
        adapter = StabilityOFTAdapter(BridgeTestLib.setupStabilityOFTAdapterOnSonic(vm, sonic));
        bridgedTokenAvalanche = BridgedToken(BridgeTestLib.setupSTBLBridged(vm, avalanche));
        bridgedTokenPlasma = BridgedToken(BridgeTestLib.setupSTBLBridged(vm, plasma));

        sonic.oapp = address(adapter);
        avalanche.oapp = address(bridgedTokenAvalanche);
        plasma.oapp = address(bridgedTokenPlasma);

        // ------------------- Upgrade XSTBL on sonic, deploy XSTBL on other chains
        _upgradeSonicPlatform();
        avalanche.xToken = createXSTBL(avalanche);
        plasma.xToken = createXSTBL(plasma);

        // ------------------- Create XTokenBridge
        sonic.xTokenBridge = createXTokenBridge(sonic);
        avalanche.xTokenBridge = createXTokenBridge(avalanche);
        plasma.xTokenBridge = createXTokenBridge(plasma);

        _setXSTBLBridge(sonic);
        _setXSTBLBridge(avalanche);
        _setXSTBLBridge(plasma);

        // ------------------- Set up STBL-bridges
        BridgeTestLib.setUpSonicAvalanche(vm, sonic, avalanche);
        BridgeTestLib.setUpSonicPlasma(vm, sonic, plasma);
        BridgeTestLib.setUpAvalanchePlasma(vm, avalanche, plasma);

        // ------------------- Provide ether to address(this) to be able to pay fees
        vm.selectFork(sonic.fork);
        deal(address(this), 100 ether);

        vm.selectFork(plasma.fork);
        deal(address(this), 100 ether);

        vm.selectFork(avalanche.fork);
        deal(address(this), 100 ether);
    }

    //endregion ------------------------------------- Constructor

    //region ------------------------------------- Unit tests
    function testStorage() public pure {
        bytes32 h = keccak256(abi.encode(uint(keccak256("erc7201:stability.XTokenBridge")) - 1)) & ~bytes32(uint(0xff));
        assertEq(h, 0x7331a1638fe957f8dc3395f52254374f52b3cbbdf185d4405a764a49dfb7f400, "storage hash");
    }

    function testViewSonic() public {
        vm.selectFork(sonic.fork);

        IXTokenBridge xTokenBridge = IXTokenBridge(sonic.xTokenBridge);
        assertEq(xTokenBridge.bridge(), sonic.oapp, "sonic: bridge");
        assertEq(xTokenBridge.xToken(), sonic.xToken, "sonic: xToken");
    }

    function testSetXTokenBridge() public {
        vm.selectFork(sonic.fork);

        IXTokenBridge xTokenBridge = IXTokenBridge(sonic.xTokenBridge);

        uint32[] memory dstEids = new uint32[](2);
        dstEids[0] = avalanche.endpointId;
        dstEids[1] = plasma.endpointId;
        address[] memory listXTokenBridges = new address[](2);
        listXTokenBridges[0] = avalanche.xTokenBridge;
        listXTokenBridges[1] = plasma.xTokenBridge;

        // ------------------- bad paths
        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        vm.prank(address(0x1234));
        xTokenBridge.setXTokenBridge(new uint32[](0), new address[](0));

        vm.expectRevert(IControllable.IncorrectArrayLength.selector);
        vm.prank(sonic.multisig);
        xTokenBridge.setXTokenBridge(dstEids, new address[](0));

        vm.expectRevert(IControllable.IncorrectArrayLength.selector);
        vm.prank(sonic.multisig);
        xTokenBridge.setXTokenBridge(new uint32[](1), listXTokenBridges);

        // ------------------- good paths
        assertEq(xTokenBridge.xTokenBridge(avalanche.endpointId), address(0), "before: avalanche bridge");
        assertEq(xTokenBridge.xTokenBridge(plasma.endpointId), address(0), "before: plasma bridge");

        vm.prank(sonic.multisig);
        xTokenBridge.setXTokenBridge(dstEids, listXTokenBridges);

        assertEq(xTokenBridge.xTokenBridge(avalanche.endpointId), avalanche.xTokenBridge, "after: avalanche bridge");
        assertEq(xTokenBridge.xTokenBridge(plasma.endpointId), plasma.xTokenBridge, "after: plasma bridge");

        dstEids = new uint32[](1);
        dstEids[0] = avalanche.endpointId;

        vm.prank(sonic.multisig);
        xTokenBridge.setXTokenBridge(dstEids, new address[](1));

        assertEq(xTokenBridge.xTokenBridge(avalanche.endpointId), address(0), "avalanche bridge is cleared");
        assertEq(xTokenBridge.xTokenBridge(plasma.endpointId), plasma.xTokenBridge, "after: plasma bridge");
    }

    function testSetLzToken() public {
        vm.selectFork(sonic.fork);

        IXTokenBridge xTokenBridge = IXTokenBridge(sonic.xTokenBridge);

        // ------------------- bad paths
        vm.expectRevert(IControllable.NotOperator.selector);
        vm.prank(address(0x1234));
        xTokenBridge.setLzToken(address(1));

        // ------------------- good paths
        assertEq(xTokenBridge.lzToken(), address(0), "before: lzToken");

        vm.prank(sonic.multisig);
        xTokenBridge.setLzToken(address(1));

        assertEq(xTokenBridge.lzToken(), address(1), "after: lzToken");

        vm.prank(sonic.multisig);
        xTokenBridge.setLzToken(address(0));

        assertEq(xTokenBridge.lzToken(), address(0), "after reset: lzToken");
    }

    function testSalvage() public {
        vm.selectFork(sonic.fork);
        address receiver = makeAddr("receiver");

        IXTokenBridge xTokenBridge = IXTokenBridge(sonic.xTokenBridge);
        IERC20 stbl = IERC20(IXSTBL(sonic.xToken).STBL());

        // ------------------- send some STBL to the xTokenBridge
        deal(address(stbl), address(this), 100e18);
        stbl.approve(address(xTokenBridge), 100e18);
        stbl.safeTransfer(address(xTokenBridge), 100e18);

        assertEq(stbl.balanceOf(address(xTokenBridge)), 100e18, "before: bridge STBL balance");
        assertEq(stbl.balanceOf(receiver), 0, "before: multisig STBL balance");

        // ------------------- bad paths
        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        vm.prank(address(0x1234));
        xTokenBridge.salvage(address(stbl), 70e18, receiver);

        // ------------------- good paths
        vm.prank(sonic.multisig);
        xTokenBridge.salvage(address(stbl), 70e18, receiver);

        assertEq(stbl.balanceOf(address(xTokenBridge)), 30e18, "after 1: bridge STBL balance");
        assertEq(stbl.balanceOf(receiver), 70e18, "after 1: receiver STBL balance");

        vm.prank(sonic.multisig);
        xTokenBridge.salvage(address(stbl), 0, receiver);

        assertEq(stbl.balanceOf(address(xTokenBridge)), 0, "after 2: bridge STBL balance");
        assertEq(stbl.balanceOf(receiver), 100e18, "after 2: receiver STBL balance");
    }

    function testSendBadPaths() public {
        _setUpXTokenBridges();

        // ------------------- provide xSTBL to the user
        vm.selectFork(sonic.fork);
        IXTokenBridge xTokenBridge = IXTokenBridge(sonic.xTokenBridge);

        deal(SonicConstantsLib.TOKEN_STBL, address(this), 100e18);

        IERC20(SonicConstantsLib.TOKEN_STBL).approve(sonic.xToken, 100e18);
        IXSTBL(sonic.xToken).enter(100e18);

        // ------------------- incorrect value
        {
            uint snapshot = vm.snapshotState();

            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT_LZRECEIVE, 0)
                .addExecutorLzComposeOption(0, GAS_LIMIT_LZCOMPOSE, 0);
            MessagingFee memory msgFee =
                IXTokenBridge(sonic.xTokenBridge).quoteSend(avalanche.endpointId, 1e18, options, false);

            vm.expectRevert(IXTokenBridge.IncorrectNativeValue.selector);
            xTokenBridge.send{value: msgFee.nativeFee + 1}(avalanche.endpointId, 1e18, msgFee, options);
            vm.revertToState(snapshot);
        }

        // ------------------- zero amount
        {
            uint snapshot = vm.snapshotState();

            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT_LZRECEIVE, 0)
                .addExecutorLzComposeOption(0, GAS_LIMIT_LZCOMPOSE, 0);
            MessagingFee memory msgFee =
                IXTokenBridge(sonic.xTokenBridge).quoteSend(avalanche.endpointId, 0, options, false);

            vm.expectRevert(IXTokenBridge.ZeroAmount.selector);
            xTokenBridge.send{value: msgFee.nativeFee}(avalanche.endpointId, 0, msgFee, options);
            vm.revertToState(snapshot);
        }

        // ------------------- sender is paused
        {
            uint snapshot = vm.snapshotState();
            vm.prank(sonic.multisig);
            IOFTPausable(sonic.oapp).setPaused(address(this), true);

            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT_LZRECEIVE, 0)
                .addExecutorLzComposeOption(0, GAS_LIMIT_LZCOMPOSE, 0);
            MessagingFee memory msgFee =
                IXTokenBridge(sonic.xTokenBridge).quoteSend(avalanche.endpointId, 1e18, options, false);

            vm.expectRevert(IXTokenBridge.SenderPaused.selector);
            xTokenBridge.send{value: msgFee.nativeFee}(avalanche.endpointId, 1e18, msgFee, options);
            vm.revertToState(snapshot);
        }

        // ------------------- lz token not supported
        {
            uint snapshot = vm.snapshotState();

            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT_LZRECEIVE, 0)
                .addExecutorLzComposeOption(0, GAS_LIMIT_LZCOMPOSE, 0);

            //  struct MessagingFee {uint256 nativeFee; uint256 lzTokenFee; }
            vm.expectRevert(IXTokenBridge.LzTokenFeeNotSupported.selector);
            xTokenBridge.send{value: 0}(avalanche.endpointId, 1e18, MessagingFee(0, 1e18), options);
            vm.revertToState(snapshot);
        }

        // ------------------- chain not supported
        {
            uint snapshot = vm.snapshotState();

            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT_LZRECEIVE, 0)
                .addExecutorLzComposeOption(0, GAS_LIMIT_LZCOMPOSE, 0);
            MessagingFee memory msgFee =
                IXTokenBridge(sonic.xTokenBridge).quoteSend(avalanche.endpointId, 1e18, options, false);

            //  struct MessagingFee {uint256 nativeFee; uint256 lzTokenFee; }
            vm.expectRevert(IXTokenBridge.ChainNotSupported.selector);
            xTokenBridge.send{value: msgFee.nativeFee}(98013078, 1e18, msgFee, options); // 98013078 is not valid endpointId
            vm.revertToState(snapshot);
        }
    }

    function testSendIncorrectAmount() public {
        vm.selectFork(sonic.fork);

        // ------------------- setup an instance of xTokenBridge with mocked xToken
        Proxy xTokenBridgeProxy = new Proxy();
        xTokenBridgeProxy.initProxy(address(new XTokenBridge(sonic.endpoint)));

        MockXToken mockedXToken = new MockXToken(SonicConstantsLib.TOKEN_STBL, 50e18);
        deal(SonicConstantsLib.TOKEN_STBL, address(mockedXToken), 50e18);

        XTokenBridge(address(xTokenBridgeProxy)).initialize(address(sonic.platform), sonic.oapp, address(mockedXToken));

        // ------------------- provide xSTBL to the user
        vm.selectFork(sonic.fork);
        IXTokenBridge xTokenBridge = IXTokenBridge(address(xTokenBridgeProxy));

        deal(SonicConstantsLib.TOKEN_STBL, address(this), 100e18);

        IERC20(SonicConstantsLib.TOKEN_STBL).approve(sonic.xToken, 100e18);
        IXSTBL(sonic.xToken).enter(100e18);

        // ------------------- chain not supported
        vm.expectRevert(IXTokenBridge.IncorrectAmountReceivedFromXToken.selector);
        xTokenBridge.send{value: 1e18}(avalanche.endpointId, 100e18, MessagingFee(1e18, 0), "");
    }

    function testComposeBadPaths() public {
        _setUpXTokenBridges();

        vm.selectFork(sonic.fork);

        vm.expectRevert(IXTokenBridge.UnauthorizedSender.selector);
        vm.prank(makeAddr("some wrong sender")); // (!)
        IOAppComposer(sonic.xTokenBridge)
            .lzCompose(
                sonic.oapp,
                bytes32(0),
                "", // compose message
                address(0), // executor
                "" // extraData
            );

        vm.expectRevert(IXTokenBridge.UntrustedOApp.selector);
        vm.prank(sonic.endpoint);
        IOAppComposer(sonic.xTokenBridge)
            .lzCompose(
                makeAddr("some other oapp"), // (!)
                bytes32(0),
                "", // compose message
                address(0), // executor
                "" // extraData
            );
    }

    function testComposeInvalidSenderXTokenBridge() public {
        _setUpXTokenBridges();

        // --------------- mint XSTBL on Sonic
        vm.selectFork(sonic.fork);
        deal(SonicConstantsLib.TOKEN_STBL, address(this), 100e18);

        IERC20(SonicConstantsLib.TOKEN_STBL).approve(sonic.xToken, 100e18);
        IXSTBL(sonic.xToken).enter(100e18);

        // --------------- send XSTBL on sonic
        vm.selectFork(sonic.fork);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT_LZRECEIVE, 0)
            .addExecutorLzComposeOption(0, GAS_LIMIT_LZCOMPOSE, 0);
        MessagingFee memory msgFee =
            IXTokenBridge(sonic.xTokenBridge).quoteSend(avalanche.endpointId, 1e18, options, false);

        vm.recordLogs();
        IXTokenBridge(sonic.xTokenBridge).send{value: msgFee.nativeFee}(avalanche.endpointId, 1e18, msgFee, options);
        bytes memory message = BridgeTestLib._extractSendMessage(vm.getRecordedLogs());

        // --------------- Simulate message receiving on avalanche
        vm.selectFork(avalanche.fork);

        {
            vm.recordLogs();
            vm.prank(avalanche.endpoint);
            IOAppReceiver(avalanche.oapp)
                .lzReceive(
                    Origin({srcEid: sonic.endpointId, sender: bytes32(uint(uint160(address(sonic.oapp)))), nonce: 1}),
                    bytes32(uint(1)),
                    message,
                    address(0), // executor
                    "" // extraData
                );
        }

        {
            (,, bytes memory composeMessage) = BridgeTestLib._extractComposeMessage(vm.getRecordedLogs());

            // now we have composeMessage with stored sonic.xTokenBridge inside
            // let's check value of sonic.xTokenBridge on avalanche side to simulate error

            uint32[] memory dstEids = new uint32[](1);
            dstEids[0] = sonic.endpointId;
            address[] memory addrs = new address[](1);
            addrs[0] = makeAddr("wrong sonic.xTokenBridge address");

            vm.prank(avalanche.multisig);
            IXTokenBridge(avalanche.xTokenBridge).setXTokenBridge(dstEids, addrs);

            vm.expectRevert(IXTokenBridge.InvalidSenderXTokenBridge.selector);
            vm.prank(avalanche.endpoint);
            IOAppComposer(avalanche.xTokenBridge)
                .lzCompose(avalanche.oapp, bytes32(uint(2)), composeMessage, address(0), "");
        }
    }

    function testComposeZeroValues() public {
        _setUpXTokenBridges();
        vm.selectFork(avalanche.fork);

        {
            bytes memory composeMessage = OFTComposeMsgCodec.encode(
                0,
                sonic.endpointId,
                0,
                // 0x[composeFrom][composeMsg], see OFTComposeMsgCodec.encode
                abi.encodePacked(OFTComposeMsgCodec.addressToBytes32(sonic.xTokenBridge), abi.encode(address(this)))
            );

            vm.expectRevert(IXTokenBridge.ZeroAmount.selector);
            vm.prank(avalanche.endpoint);
            IOAppComposer(avalanche.xTokenBridge)
                .lzCompose(avalanche.oapp, bytes32(uint(2)), composeMessage, address(0), "");
        }

        {
            bytes memory composeMessage = OFTComposeMsgCodec.encode(
                0,
                sonic.endpointId,
                1e18,
                // 0x[composeFrom][composeMsg], see OFTComposeMsgCodec.encode
                abi.encodePacked(OFTComposeMsgCodec.addressToBytes32(sonic.xTokenBridge), abi.encode(address(0)))
            );

            vm.expectRevert(IXTokenBridge.IncorrectReceiver.selector);
            vm.prank(avalanche.endpoint);
            IOAppComposer(avalanche.xTokenBridge)
                .lzCompose(avalanche.oapp, bytes32(uint(2)), composeMessage, address(0), "");
        }
    }

    //endregion ------------------------------------- Unit tests

    //region ------------------------------------- Send XSTBL between chains
    function testSendXSTBLFromSonicToPlasma() public {
        _setUpXTokenBridges();

        // --------------- mint XSTBL on Sonic
        vm.selectFork(sonic.fork);
        deal(SonicConstantsLib.TOKEN_STBL, address(this), 100e18);

        IERC20(SonicConstantsLib.TOKEN_STBL).approve(sonic.xToken, 100e18);
        IXSTBL(sonic.xToken).enter(100e18);

        // --------------- send XSTBL from Sonic to Plasma
        Results memory r1 = _testSendXSTBL(sonic, plasma, 70e18, 0);

        assertEq(r1.srcBefore.balanceUserXSTBL, 100e18, "sonic: user xSTBL before");
        assertEq(r1.srcAfter.balanceUserXSTBL, 30e18, "sonic: user xSTBL after");
        assertEq(r1.targetBefore.balanceUserXSTBL, 0, "plasma: user xSTBL before");
        assertEq(r1.targetAfter.balanceUserXSTBL, 70e18, "plasma: user xSTBL after");

        assertEq(r1.srcBefore.balanceXTokenBridgeSTBL, 0, "sonic: xTokenBridge STBL before");
        assertEq(r1.srcAfter.balanceXTokenBridgeSTBL, 0, "sonic: xTokenBridge STBL after");
        assertEq(r1.targetBefore.balanceXTokenBridgeSTBL, 0, "plasma: xTokenBridge STBL before");
        assertEq(r1.targetAfter.balanceXTokenBridgeSTBL, 0, "plasma: xTokenBridge STBL after");

        assertEq(r1.srcAfter.balanceXTokenSTBL, r1.srcBefore.balanceXTokenSTBL - 70e18, "sonic: xToken STBL after");
        assertEq(r1.targetAfter.balanceXTokenSTBL, 70e18, "plasma: STBL staked to XSTBL");

        assertEq(r1.srcAfter.balanceOappSTBL, 70e18, "sonic: expected amount of locked STBL in the bridge");

        // --------------- send XSTBL from Sonic to Plasma 2
        Results memory r2 = _testSendXSTBL(sonic, plasma, 30e18, 1);

        assertEq(r2.srcBefore.balanceUserXSTBL, 30e18, "sonic: user xSTBL before 2");
        assertEq(r2.srcAfter.balanceUserXSTBL, 0, "sonic: user xSTBL after 2");
        assertEq(r2.targetBefore.balanceUserXSTBL, 70e18, "plasma: user xSTBL before 2");
        assertEq(r2.targetAfter.balanceUserXSTBL, 100e18, "plasma: user xSTBL after 2");

        assertEq(r2.srcBefore.balanceXTokenBridgeSTBL, 0, "sonic: xTokenBridge STBL before 2");
        assertEq(r2.srcAfter.balanceXTokenBridgeSTBL, 0, "sonic: xTokenBridge STBL after 2");
        assertEq(r2.targetBefore.balanceXTokenBridgeSTBL, 0, "plasma: xTokenBridge STBL before 2");
        assertEq(r2.targetAfter.balanceXTokenBridgeSTBL, 0, "plasma: xTokenBridge STBL after 2");

        assertEq(r2.srcAfter.balanceXTokenSTBL, r2.srcBefore.balanceXTokenSTBL - 30e18, "sonic: xToken STBL after 2");
        assertEq(r2.targetAfter.balanceXTokenSTBL, 100e18, "plasma: STBL staked to XSTBL 2");

        assertEq(r2.srcAfter.balanceOappSTBL, 100e18, "sonic: expected amount of locked STBL in the bridge 2");

        // --------------- send XSTBL back from Plasma to Sonic
        Results memory r3 = _testSendXSTBL(plasma, sonic, 100e18, 2);

        assertEq(r3.srcBefore.balanceUserXSTBL, 100e18, "plasma: user xSTBL before 3");
        assertEq(r3.srcAfter.balanceUserXSTBL, 0, "plasma: user xSTBL after 3");
        assertEq(r3.targetBefore.balanceUserXSTBL, 0, "sonic: user xSTBL before 3");
        assertEq(r3.targetAfter.balanceUserXSTBL, 100e18, "sonic: user xSTBL after 3");

        assertEq(r3.srcBefore.balanceXTokenBridgeSTBL, 0, "plasma: xTokenBridge STBL before 3");
        assertEq(r3.srcAfter.balanceXTokenBridgeSTBL, 0, "plasma: xTokenBridge STBL after 3");
        assertEq(r3.targetBefore.balanceXTokenBridgeSTBL, 0, "sonic: xTokenBridge STBL before 3");
        assertEq(r3.targetAfter.balanceXTokenBridgeSTBL, 0, "sonic: xTokenBridge STBL after 3");

        assertEq(r3.srcAfter.balanceXTokenSTBL, 0, "plasma: xToken STBL after 3");
        assertEq(
            r3.targetAfter.balanceXTokenSTBL,
            r1.srcBefore.balanceXTokenSTBL,
            "sonic: all STBL were returned back to XSTBL"
        );

        assertEq(r3.srcAfter.balanceOappSTBL, 0, "plasma: expected amount of locked STBL in the bridge 3");
    }

    function testSendXSTBLFromAvalancheToPlasma() public {
        _setUpXTokenBridges();

        // --------------- mint XSTBL on Sonic
        vm.selectFork(sonic.fork);
        deal(SonicConstantsLib.TOKEN_STBL, address(this), 100e18);

        IERC20(SonicConstantsLib.TOKEN_STBL).approve(sonic.xToken, 100e18);
        IXSTBL(sonic.xToken).enter(100e18);

        // --------------- send XSTBL from Sonic to Avalanche
        _testSendXSTBL(sonic, avalanche, 100e18, 1345);

        // --------------- send XSTBL from avalanche to Plasma
        Results memory r1 = _testSendXSTBL(avalanche, plasma, 70e18, 0);

        assertEq(r1.srcBefore.balanceUserXSTBL, 100e18, "avalanche: user xSTBL before");
        assertEq(r1.srcAfter.balanceUserXSTBL, 30e18, "avalanche: user xSTBL after");
        assertEq(r1.targetBefore.balanceUserXSTBL, 0, "plasma: user xSTBL before");
        assertEq(r1.targetAfter.balanceUserXSTBL, 70e18, "plasma: user xSTBL after");

        assertEq(r1.srcBefore.balanceXTokenBridgeSTBL, 0, "avalanche: xTokenBridge STBL before");
        assertEq(r1.srcAfter.balanceXTokenBridgeSTBL, 0, "avalanche: xTokenBridge STBL after");
        assertEq(r1.targetBefore.balanceXTokenBridgeSTBL, 0, "plasma: xTokenBridge STBL before");
        assertEq(r1.targetAfter.balanceXTokenBridgeSTBL, 0, "plasma: xTokenBridge STBL after");

        assertEq(r1.srcAfter.balanceXTokenSTBL, r1.srcBefore.balanceXTokenSTBL - 70e18, "avalanche: xToken STBL after");
        assertEq(r1.targetAfter.balanceXTokenSTBL, 70e18, "plasma: STBL staked to XSTBL");

        assertEq(r1.srcAfter.balanceOappSTBL, 0, "avalanche: expected amount of locked STBL in the bridge");

        // --------------- send XSTBL from avalanche to Plasma 2
        Results memory r2 = _testSendXSTBL(avalanche, plasma, 30e18, 1);

        assertEq(r2.srcBefore.balanceUserXSTBL, 30e18, "avalanche: user xSTBL before 2");
        assertEq(r2.srcAfter.balanceUserXSTBL, 0, "avalanche: user xSTBL after 2");
        assertEq(r2.targetBefore.balanceUserXSTBL, 70e18, "plasma: user xSTBL before 2");
        assertEq(r2.targetAfter.balanceUserXSTBL, 100e18, "plasma: user xSTBL after 2");

        assertEq(r2.srcBefore.balanceXTokenBridgeSTBL, 0, "avalanche: xTokenBridge STBL before 2");
        assertEq(r2.srcAfter.balanceXTokenBridgeSTBL, 0, "avalanche: xTokenBridge STBL after 2");
        assertEq(r2.targetBefore.balanceXTokenBridgeSTBL, 0, "plasma: xTokenBridge STBL before 2");
        assertEq(r2.targetAfter.balanceXTokenBridgeSTBL, 0, "plasma: xTokenBridge STBL after 2");

        assertEq(
            r2.srcAfter.balanceXTokenSTBL, r2.srcBefore.balanceXTokenSTBL - 30e18, "avalanche: xToken STBL after 2"
        );
        assertEq(r2.targetAfter.balanceXTokenSTBL, 100e18, "plasma: STBL staked to XSTBL 2");

        assertEq(r2.srcAfter.balanceOappSTBL, 0, "avalanche: expected amount of locked STBL in the bridge 2");

        // --------------- send XSTBL back from Plasma to avalanche
        Results memory r3 = _testSendXSTBL(plasma, avalanche, 100e18, 2);

        assertEq(r3.srcBefore.balanceUserXSTBL, 100e18, "plasma: user xSTBL before 3");
        assertEq(r3.srcAfter.balanceUserXSTBL, 0, "plasma: user xSTBL after 3");
        assertEq(r3.targetBefore.balanceUserXSTBL, 0, "avalanche: user xSTBL before 3");
        assertEq(r3.targetAfter.balanceUserXSTBL, 100e18, "avalanche: user xSTBL after 3");

        assertEq(r3.srcBefore.balanceXTokenBridgeSTBL, 0, "plasma: xTokenBridge STBL before 3");
        assertEq(r3.srcAfter.balanceXTokenBridgeSTBL, 0, "plasma: xTokenBridge STBL after 3");
        assertEq(r3.targetBefore.balanceXTokenBridgeSTBL, 0, "avalanche: xTokenBridge STBL before 3");
        assertEq(r3.targetAfter.balanceXTokenBridgeSTBL, 0, "avalanche: xTokenBridge STBL after 3");

        assertEq(r3.srcAfter.balanceXTokenSTBL, 0, "plasma: xToken STBL after 3");
        assertEq(
            r3.targetAfter.balanceXTokenSTBL,
            r1.srcBefore.balanceXTokenSTBL,
            "avalanche: all STBL were returned back to XSTBL"
        );

        assertEq(r3.srcAfter.balanceOappSTBL, 0, "plasma: expected amount of locked STBL in the bridge 3");
    }

    //endregion ------------------------------------- Send XSTBL between chains

    //region ------------------------------------- Unit tests
    function _testSendXSTBL(
        BridgeTestLib.ChainConfig memory src,
        BridgeTestLib.ChainConfig memory dest,
        uint amount_,
        uint guidId_
    ) internal returns (Results memory r) {
        // --------------- initial state on src
        vm.selectFork(dest.fork);
        r.targetBefore = getBalances(dest, address(this));

        // --------------- send XSTBL on src
        vm.selectFork(src.fork);
        r.srcBefore = getBalances(src, address(this));

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT_LZRECEIVE, 0)
            .addExecutorLzComposeOption(0, GAS_LIMIT_LZCOMPOSE, 0);
        MessagingFee memory msgFee = IXTokenBridge(src.xTokenBridge).quoteSend(dest.endpointId, amount_, options, false);

        vm.recordLogs();
        IXTokenBridge(src.xTokenBridge).send{value: msgFee.nativeFee}(dest.endpointId, amount_, msgFee, options);
        bytes memory message = BridgeTestLib._extractSendMessage(vm.getRecordedLogs());

        // --------------- Simulate message receiving on dest
        vm.selectFork(dest.fork);

        Origin memory origin =
            Origin({srcEid: src.endpointId, sender: bytes32(uint(uint160(address(src.oapp)))), nonce: 1});

        // --------------- lzReceive
        {
            uint gasBefore = gasleft();
            vm.recordLogs();
            vm.prank(dest.endpoint);
            IOAppReceiver(dest.oapp)
                .lzReceive(
                    origin,
                    bytes32(guidId_), // guid: actual value doesn't matter
                    message,
                    address(0), // executor
                    "" // extraData
                );
            assertLt(gasBefore - gasleft(), GAS_LIMIT_LZRECEIVE, "lzReceive gas limit exceeded");
            console.log("gasBefore - gasleft() (lzReceive):", gasBefore - gasleft());
        }

        // --------------- lzCompose

        // see comment from OFTCore:
        // @dev Stores the lzCompose payload that will be executed in a separate tx.
        // Standardizes functionality for executing arbitrary contract invocation on some non-evm chains.
        // @dev The off-chain executor will listen and process the msg based on the src-chain-callers compose options passed.
        // @dev The index is used when a OApp needs to compose multiple msgs on lzReceive.
        // For default OFT implementation there is only 1 compose msg per lzReceive, thus its always 0.
        // endpoint.sendCompose(toAddress, _guid, 0 /* the index of the composed message*/, composeMsg);
        // interface IMessagingComposer {
        // event ComposeSent(address from, address to, bytes32 guid, uint16 index, bytes message);

        {
            (address from, address to, bytes memory composeMessage) =
                BridgeTestLib._extractComposeMessage(vm.getRecordedLogs());
            uint gasBefore = gasleft();
            vm.recordLogs();
            vm.prank(dest.endpoint);
            IOAppComposer(dest.xTokenBridge)
                .lzCompose(
                    dest.oapp,
                    bytes32(guidId_), // guid: actual value doesn't matter
                    composeMessage,
                    address(0), // executor
                    "" // extraData
                );
            assertLt(gasBefore - gasleft(), GAS_LIMIT_LZCOMPOSE, "lzCompoze gas limit exceeded");
            console.log("gasBefore - gasleft() (compose):", gasBefore - gasleft());

            assertEq(from, dest.oapp, "invalid compose from");
            assertEq(to, address(dest.xTokenBridge), "invalid compose to");
        }

        r.targetAfter = getBalances(dest, address(this));

        // --------------- src
        vm.selectFork(src.fork);
        r.srcAfter = getBalances(src, address(this));

        //        showResults(r);
        //
        //        console.log("user", address(this));
        //        console.log("src.xToken", src.xToken);
        //        console.log("src.oapp", src.oapp);
        //        console.log("src.xTokenBridge", src.xTokenBridge);
        //        console.log("src.STBL", IXSTBL(src.xToken).STBL());
        //
        //        vm.selectFork(dest.fork);
        //        console.log("dest.xToken", dest.xToken);
        //        console.log("dest.oapp", dest.oapp);
        //        console.log("dest.xTokenBridge", dest.xTokenBridge);
        //        console.log("dest.STBL", IXSTBL(dest.xToken).STBL());
    }

    //endregion ------------------------------------- Unit tests

    //region ------------------------------------- Internal utils
    function getBalances(
        BridgeTestLib.ChainConfig memory chain,
        address user
    ) internal view returns (ChainResults memory results) {
        IERC20 stbl = IERC20(IXSTBL(chain.xToken).STBL());

        results.balanceUserSTBL = stbl.balanceOf(user);
        results.balanceUserXSTBL = IERC20(chain.xToken).balanceOf(user);
        results.balanceOappSTBL = stbl.balanceOf(chain.oapp);
        results.balanceXTokenSTBL = stbl.balanceOf(chain.xToken);
        results.balanceUserEther = user.balance;
        results.balanceXTokenBridgeSTBL = stbl.balanceOf(chain.xTokenBridge);
    }

    function createXSTBL(BridgeTestLib.ChainConfig memory chain) internal returns (address) {
        vm.selectFork(chain.fork);

        Proxy xStakingProxy = new Proxy();
        xStakingProxy.initProxy(address(new XStaking()));

        Proxy xSTBLProxy = new Proxy();
        xSTBLProxy.initProxy(address(new XSTBL()));

        XSTBL(address(xSTBLProxy))
            .initialize(
                address(chain.platform),
                chain.oapp,
                address(xStakingProxy),
                address(0) // todo probably zero is not enough for all tests
            );

        XStaking(address(xStakingProxy)).initialize(address(chain.platform), address(xSTBLProxy));

        return address(xSTBLProxy);
    }

    function createXTokenBridge(BridgeTestLib.ChainConfig memory chain) internal returns (address) {
        vm.selectFork(chain.fork);

        Proxy xTokenBridgeProxy = new Proxy();
        xTokenBridgeProxy.initProxy(address(new XTokenBridge(chain.endpoint)));

        XTokenBridge(address(xTokenBridgeProxy)).initialize(address(chain.platform), chain.oapp, chain.xToken);

        return address(xTokenBridgeProxy);
    }

    function showResults(Results memory r) internal pure {
        showChainResults("src.before", r.srcBefore);
        showChainResults("target.before", r.targetBefore);
        showChainResults("src.after", r.srcAfter);
        showChainResults("target.after", r.targetAfter);
    }

    function showChainResults(string memory label, ChainResults memory r) internal pure {
        console.log("------------------ %s ------------------", label);
        console.log("balanceUserSTBL", r.balanceUserSTBL);
        console.log("balanceUserXSTBL", r.balanceUserXSTBL);
        console.log("balanceOappSTBL", r.balanceOappSTBL);
        console.log("balanceXTokenSTBL", r.balanceXTokenSTBL);
        console.log("balanceUserEther", r.balanceUserEther);
        console.log("balanceXTokenBridgeSTBL", r.balanceXTokenBridgeSTBL);
    }

    function _setXTokenBridge(
        BridgeTestLib.ChainConfig memory chain,
        BridgeTestLib.ChainConfig memory c1,
        BridgeTestLib.ChainConfig memory c2
    ) internal {
        vm.selectFork(chain.fork);

        uint32[] memory dstEids = new uint32[](2);
        dstEids[0] = c1.endpointId;
        dstEids[1] = c2.endpointId;
        address[] memory bridges = new address[](2);
        bridges[0] = c1.xTokenBridge;
        bridges[1] = c2.xTokenBridge;

        vm.prank(chain.multisig);
        IXTokenBridge(chain.xTokenBridge).setXTokenBridge(dstEids, bridges);
    }

    function _setXSTBLBridge(BridgeTestLib.ChainConfig memory chain) internal {
        vm.selectFork(chain.fork);
        vm.prank(chain.multisig);
        IXSTBL(chain.xToken).setBridge(chain.xTokenBridge, true);
    }

    function _setUpXTokenBridges() internal {
        _setXTokenBridge(sonic, avalanche, plasma);
        _setXTokenBridge(avalanche, sonic, plasma);
        _setXTokenBridge(plasma, sonic, avalanche);
    }

    //endregion ------------------------------------- Internal utils

    //region ------------------------------------- Helpers
    function _upgradeSonicPlatform() internal {
        vm.selectFork(sonic.fork);
        rewind(1 days);

        IPlatform platform = IPlatform(SonicConstantsLib.PLATFORM);

        address[] memory proxies = new address[](1);
        address[] memory implementations = new address[](1);

        proxies[0] = SonicConstantsLib.TOKEN_XSTBL;
        implementations[0] = address(new XSTBL());

        //        vm.startPrank(SonicConstantsLib.MULTISIG);
        //        platform.cancelUpgrade();

        vm.startPrank(SonicConstantsLib.MULTISIG);
        platform.announcePlatformUpgrade("2025.10.02-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }
    //endregion ------------------------------------- Helpers
}
