// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {XToken} from "../../src/tokenomics/XToken.sol";
import {BridgeTestLib} from "./libs/BridgeTestLib.sol";
import {console, Test, Vm} from "forge-std/Test.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";
import {XTokenBridge} from "../../src/tokenomics/XTokenBridge.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {IXToken} from "../../src/interfaces/IXToken.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IOFTPausable} from "../../src/interfaces/IOFTPausable.sol";
import {IXTokenBridge} from "../../src/interfaces/IXTokenBridge.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TokenOFTAdapter} from "../../src/tokenomics/TokenOFTAdapter.sol";
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
import {ILayerZeroEndpointV2} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";

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

    TokenOFTAdapter internal adapter;
    BridgedToken internal bridgedTokenAvalanche;
    BridgedToken internal bridgedTokenPlasma;

    BridgeTestLib.ChainConfig internal sonic;
    BridgeTestLib.ChainConfig internal avalanche;
    BridgeTestLib.ChainConfig internal plasma;

    address private constant TEST_DELEGATOR = address(0x999);

    struct ChainResults {
        uint balanceUserMainToken;
        uint balanceUserXToken;
        uint balanceOappMainToken;
        uint balanceXTokenMainToken;
        uint balanceUserEther;
        uint balanceXTokenBridgedMainToken;
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

            sonic = BridgeTestLib.createConfigSonic(vm, forkSonic, TEST_DELEGATOR);
            avalanche = BridgeTestLib.createConfigAvalanche(vm, forkAvalanche, TEST_DELEGATOR);
            plasma = BridgeTestLib.createConfigPlasma(vm, forkPlasma, TEST_DELEGATOR);
        }

        // ------------------- Create bridge for STBL
        adapter = TokenOFTAdapter(BridgeTestLib.setupTokenOFTAdapterOnSonic(vm, sonic));
        bridgedTokenAvalanche = BridgedToken(BridgeTestLib.setupBridgedMainToken(vm, avalanche));
        bridgedTokenPlasma = BridgedToken(BridgeTestLib.setupBridgedMainToken(vm, plasma));

        sonic.oapp = address(adapter);
        avalanche.oapp = address(bridgedTokenAvalanche);
        plasma.oapp = address(bridgedTokenPlasma);

        // ------------------- Upgrade xToken on sonic, deploy xToken on other chains
        _upgradeSonicPlatform();
        avalanche.xToken = createXToken(avalanche);
        plasma.xToken = createXToken(plasma);

        // ------------------- Create XTokenBridge
        sonic.xTokenBridge = createXTokenBridge(sonic);
        avalanche.xTokenBridge = createXTokenBridge(avalanche);
        plasma.xTokenBridge = createXTokenBridge(plasma);

        _setXTokenBridge(sonic);
        _setXTokenBridge(avalanche);
        _setXTokenBridge(plasma);

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

    function testSalvage() public {
        vm.selectFork(sonic.fork);
        address receiver = makeAddr("receiver");

        IXTokenBridge xTokenBridge = IXTokenBridge(sonic.xTokenBridge);
        IERC20 stbl = IERC20(IXToken(sonic.xToken).token());

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

        // ------------------- provide xToken to the user
        vm.selectFork(sonic.fork);
        IXTokenBridge xTokenBridge = IXTokenBridge(sonic.xTokenBridge);

        deal(SonicConstantsLib.TOKEN_STBL, address(this), 100e18);

        IERC20(SonicConstantsLib.TOKEN_STBL).approve(sonic.xToken, 100e18);
        IXToken(sonic.xToken).enter(100e18);

        // ------------------- incorrect value
        {
            uint snapshot = vm.snapshotState();

            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT_LZRECEIVE, 0)
                .addExecutorLzComposeOption(0, GAS_LIMIT_LZCOMPOSE, 0);
            MessagingFee memory msgFee =
                IXTokenBridge(sonic.xTokenBridge).quoteSend(avalanche.endpointId, 1e18, options);

            vm.expectRevert(IXTokenBridge.IncorrectNativeValue.selector);
            xTokenBridge.send{value: msgFee.nativeFee + 1}(avalanche.endpointId, 1e18, msgFee, options);
            vm.revertToState(snapshot);
        }

        // ------------------- zero amount
        {
            uint snapshot = vm.snapshotState();

            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT_LZRECEIVE, 0)
                .addExecutorLzComposeOption(0, GAS_LIMIT_LZCOMPOSE, 0);
            MessagingFee memory msgFee = IXTokenBridge(sonic.xTokenBridge).quoteSend(avalanche.endpointId, 0, options);

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
                IXTokenBridge(sonic.xTokenBridge).quoteSend(avalanche.endpointId, 1e18, options);

            vm.expectRevert(IXTokenBridge.SenderPaused.selector);
            xTokenBridge.send{value: msgFee.nativeFee}(avalanche.endpointId, 1e18, msgFee, options);
            vm.revertToState(snapshot);
        }

        // ------------------- chain not supported
        {
            uint snapshot = vm.snapshotState();

            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT_LZRECEIVE, 0)
                .addExecutorLzComposeOption(0, GAS_LIMIT_LZCOMPOSE, 0);
            MessagingFee memory msgFee =
                IXTokenBridge(sonic.xTokenBridge).quoteSend(avalanche.endpointId, 1e18, options);

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

        // ------------------- provide xToken to the user
        vm.selectFork(sonic.fork);
        IXTokenBridge xTokenBridge = IXTokenBridge(address(xTokenBridgeProxy));

        deal(SonicConstantsLib.TOKEN_STBL, address(this), 100e18);

        IERC20(SonicConstantsLib.TOKEN_STBL).approve(sonic.xToken, 100e18);
        IXToken(sonic.xToken).enter(100e18);

        // ------------------- chain not supported
        vm.expectRevert(); // IXTokenBridge.IncorrectAmountReceivedFromXToken.selector);
        xTokenBridge.send{value: 1e18}(avalanche.endpointId, 100e18, MessagingFee({nativeFee: 1e18, lzTokenFee: 0}), "");
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

        // --------------- mint xToken on Sonic
        vm.selectFork(sonic.fork);
        deal(SonicConstantsLib.TOKEN_STBL, address(this), 100e18);

        IERC20(SonicConstantsLib.TOKEN_STBL).approve(sonic.xToken, 100e18);
        IXToken(sonic.xToken).enter(100e18);

        // --------------- send xToken on sonic
        vm.selectFork(sonic.fork);

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT_LZRECEIVE, 0)
            .addExecutorLzComposeOption(0, GAS_LIMIT_LZCOMPOSE, 0);
        MessagingFee memory msgFee = IXTokenBridge(sonic.xTokenBridge).quoteSend(avalanche.endpointId, 1e18, options);

        vm.recordLogs();
        IXTokenBridge(sonic.xTokenBridge).send{value: msgFee.nativeFee}(avalanche.endpointId, 1e18, msgFee, options);
        (bytes memory message,) = BridgeTestLib._extractSendMessage(vm.getRecordedLogs());

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

    //region ------------------------------------- Send xToken between chains
    function testSendXTokenFromSonicToPlasma() public {
        _setUpXTokenBridges();

        // --------------- mint xToken on Sonic
        vm.selectFork(sonic.fork);
        deal(SonicConstantsLib.TOKEN_STBL, address(this), 100e18);

        IERC20(SonicConstantsLib.TOKEN_STBL).approve(sonic.xToken, 100e18);
        IXToken(sonic.xToken).enter(100e18);

        // --------------- send xToken from Sonic to Plasma
        Results memory r1 = _testSendXToken(sonic, plasma, 70e18, 0);

        assertEq(r1.srcBefore.balanceUserXToken, 100e18, "sonic: user xToken before");
        assertEq(r1.srcAfter.balanceUserXToken, 30e18, "sonic: user xToken after");
        assertEq(r1.targetBefore.balanceUserXToken, 0, "plasma: user xToken before");
        assertEq(r1.targetAfter.balanceUserXToken, 70e18, "plasma: user xToken after");

        assertEq(r1.srcBefore.balanceXTokenBridgedMainToken, 0, "sonic: xTokenBridge main-token before");
        assertEq(r1.srcAfter.balanceXTokenBridgedMainToken, 0, "sonic: xTokenBridge main-token after");
        assertEq(r1.targetBefore.balanceXTokenBridgedMainToken, 0, "plasma: xTokenBridge main-token before");
        assertEq(r1.targetAfter.balanceXTokenBridgedMainToken, 0, "plasma: xTokenBridge main-token after");

        assertEq(
            r1.srcAfter.balanceXTokenMainToken,
            r1.srcBefore.balanceXTokenMainToken - 70e18,
            "sonic: xToken main-token after"
        );
        assertEq(r1.targetAfter.balanceXTokenMainToken, 70e18, "plasma: main-token staked to xToken");

        assertEq(r1.srcAfter.balanceOappMainToken, 70e18, "sonic: expected amount of locked main-token in the bridge");

        // --------------- send xToken from Sonic to Plasma 2
        Results memory r2 = _testSendXToken(sonic, plasma, 30e18, 1);

        assertEq(r2.srcBefore.balanceUserXToken, 30e18, "sonic: user xToken before 2");
        assertEq(r2.srcAfter.balanceUserXToken, 0, "sonic: user xToken after 2");
        assertEq(r2.targetBefore.balanceUserXToken, 70e18, "plasma: user xToken before 2");
        assertEq(r2.targetAfter.balanceUserXToken, 100e18, "plasma: user xToken after 2");

        assertEq(r2.srcBefore.balanceXTokenBridgedMainToken, 0, "sonic: xTokenBridge main-token before 2");
        assertEq(r2.srcAfter.balanceXTokenBridgedMainToken, 0, "sonic: xTokenBridge main-token after 2");
        assertEq(r2.targetBefore.balanceXTokenBridgedMainToken, 0, "plasma: xTokenBridge main-token before 2");
        assertEq(r2.targetAfter.balanceXTokenBridgedMainToken, 0, "plasma: xTokenBridge main-token after 2");

        assertEq(
            r2.srcAfter.balanceXTokenMainToken,
            r2.srcBefore.balanceXTokenMainToken - 30e18,
            "sonic: xToken main-token after 2"
        );
        assertEq(r2.targetAfter.balanceXTokenMainToken, 100e18, "plasma: main-token staked to xToken 2");

        assertEq(
            r2.srcAfter.balanceOappMainToken, 100e18, "sonic: expected amount of locked main-token in the bridge 2"
        );

        // --------------- send xToken back from Plasma to Sonic
        Results memory r3 = _testSendXToken(plasma, sonic, 100e18, 2);

        assertEq(r3.srcBefore.balanceUserXToken, 100e18, "plasma: user xToken before 3");
        assertEq(r3.srcAfter.balanceUserXToken, 0, "plasma: user xToken after 3");
        assertEq(r3.targetBefore.balanceUserXToken, 0, "sonic: user xToken before 3");
        assertEq(r3.targetAfter.balanceUserXToken, 100e18, "sonic: user xToken after 3");

        assertEq(r3.srcBefore.balanceXTokenBridgedMainToken, 0, "plasma: xTokenBridge main-token before 3");
        assertEq(r3.srcAfter.balanceXTokenBridgedMainToken, 0, "plasma: xTokenBridge main-token after 3");
        assertEq(r3.targetBefore.balanceXTokenBridgedMainToken, 0, "sonic: xTokenBridge main-token before 3");
        assertEq(r3.targetAfter.balanceXTokenBridgedMainToken, 0, "sonic: xTokenBridge main-token after 3");

        assertEq(r3.srcAfter.balanceXTokenMainToken, 0, "plasma: xToken main-token after 3");
        assertEq(
            r3.targetAfter.balanceXTokenMainToken,
            r1.srcBefore.balanceXTokenMainToken,
            "sonic: all main-token were returned back to xToken"
        );

        assertEq(r3.srcAfter.balanceOappMainToken, 0, "plasma: expected amount of locked main-token in the bridge 3");
    }

    function testSendXTokenFromAvalancheToPlasma() public {
        _setUpXTokenBridges();

        // --------------- mint xToken on Sonic
        vm.selectFork(sonic.fork);
        deal(SonicConstantsLib.TOKEN_STBL, address(this), 100e18);

        IERC20(SonicConstantsLib.TOKEN_STBL).approve(sonic.xToken, 100e18);
        IXToken(sonic.xToken).enter(100e18);

        // --------------- send xToken from Sonic to Avalanche
        _testSendXToken(sonic, avalanche, 100e18, 1345);

        // --------------- send xToken from avalanche to Plasma
        Results memory r1 = _testSendXToken(avalanche, plasma, 70e18, 0);

        assertEq(r1.srcBefore.balanceUserXToken, 100e18, "avalanche: user xToken before");
        assertEq(r1.srcAfter.balanceUserXToken, 30e18, "avalanche: user xToken after");
        assertEq(r1.targetBefore.balanceUserXToken, 0, "plasma: user xToken before");
        assertEq(r1.targetAfter.balanceUserXToken, 70e18, "plasma: user xToken after");

        assertEq(r1.srcBefore.balanceXTokenBridgedMainToken, 0, "avalanche: xTokenBridge main-token before");
        assertEq(r1.srcAfter.balanceXTokenBridgedMainToken, 0, "avalanche: xTokenBridge main-token after");
        assertEq(r1.targetBefore.balanceXTokenBridgedMainToken, 0, "plasma: xTokenBridge main-token before");
        assertEq(r1.targetAfter.balanceXTokenBridgedMainToken, 0, "plasma: xTokenBridge main-token after");

        assertEq(
            r1.srcAfter.balanceXTokenMainToken,
            r1.srcBefore.balanceXTokenMainToken - 70e18,
            "avalanche: xToken main-token after"
        );
        assertEq(r1.targetAfter.balanceXTokenMainToken, 70e18, "plasma: main-token staked to xToken");

        assertEq(r1.srcAfter.balanceOappMainToken, 0, "avalanche: expected amount of locked STBL in the bridge");

        // --------------- send xToken from avalanche to Plasma 2
        Results memory r2 = _testSendXToken(avalanche, plasma, 30e18, 1);

        assertEq(r2.srcBefore.balanceUserXToken, 30e18, "avalanche: user xToken before 2");
        assertEq(r2.srcAfter.balanceUserXToken, 0, "avalanche: user xToken after 2");
        assertEq(r2.targetBefore.balanceUserXToken, 70e18, "plasma: user xToken before 2");
        assertEq(r2.targetAfter.balanceUserXToken, 100e18, "plasma: user xToken after 2");

        assertEq(r2.srcBefore.balanceXTokenBridgedMainToken, 0, "avalanche: xTokenBridge main-token before 2");
        assertEq(r2.srcAfter.balanceXTokenBridgedMainToken, 0, "avalanche: xTokenBridge main-token after 2");
        assertEq(r2.targetBefore.balanceXTokenBridgedMainToken, 0, "plasma: xTokenBridge main-token before 2");
        assertEq(r2.targetAfter.balanceXTokenBridgedMainToken, 0, "plasma: xTokenBridge main-token after 2");

        assertEq(
            r2.srcAfter.balanceXTokenMainToken,
            r2.srcBefore.balanceXTokenMainToken - 30e18,
            "avalanche: xToken main-token after 2"
        );
        assertEq(r2.targetAfter.balanceXTokenMainToken, 100e18, "plasma: main-token staked to xToken 2");

        assertEq(r2.srcAfter.balanceOappMainToken, 0, "avalanche: expected amount of locked main-token in the bridge 2");

        // --------------- send xToken back from Plasma to avalanche
        Results memory r3 = _testSendXToken(plasma, avalanche, 100e18, 2);

        assertEq(r3.srcBefore.balanceUserXToken, 100e18, "plasma: user xToken before 3");
        assertEq(r3.srcAfter.balanceUserXToken, 0, "plasma: user xToken after 3");
        assertEq(r3.targetBefore.balanceUserXToken, 0, "avalanche: user xToken before 3");
        assertEq(r3.targetAfter.balanceUserXToken, 100e18, "avalanche: user xToken after 3");

        assertEq(r3.srcBefore.balanceXTokenBridgedMainToken, 0, "plasma: xTokenBridge main-token before 3");
        assertEq(r3.srcAfter.balanceXTokenBridgedMainToken, 0, "plasma: xTokenBridge main-token after 3");
        assertEq(r3.targetBefore.balanceXTokenBridgedMainToken, 0, "avalanche: xTokenBridge main-token before 3");
        assertEq(r3.targetAfter.balanceXTokenBridgedMainToken, 0, "avalanche: xTokenBridge main-token after 3");

        assertEq(r3.srcAfter.balanceXTokenMainToken, 0, "plasma: xToken main-token after 3");
        assertEq(
            r3.targetAfter.balanceXTokenMainToken,
            r1.srcBefore.balanceXTokenMainToken,
            "avalanche: all STBL were returned back to xToken"
        );

        assertEq(r3.srcAfter.balanceOappMainToken, 0, "plasma: expected amount of locked main-token in the bridge 3");
    }

    function testReceiveThroughEndpoint() public {
        _setUpXTokenBridges();

        // --------------- provide xToken to the user
        vm.selectFork(sonic.fork);

        deal(SonicConstantsLib.TOKEN_STBL, address(this), 100e18);
        IERC20(SonicConstantsLib.TOKEN_STBL).approve(sonic.xToken, 100e18);
        IXToken(sonic.xToken).enter(100e18);

        // --------------- send xToken on src
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT_LZRECEIVE, 0)
            .addExecutorLzComposeOption(0, GAS_LIMIT_LZCOMPOSE, 0);
        MessagingFee memory msgFee = IXTokenBridge(sonic.xTokenBridge).quoteSend(plasma.endpointId, 1e18, options);

        vm.recordLogs();
        IXTokenBridge(sonic.xTokenBridge).send{value: msgFee.nativeFee}(plasma.endpointId, 1e18, msgFee, options);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        // decode Layer Zero's event PacketSent
        (bytes memory message, bytes32 guidId_) = BridgeTestLib._extractSendMessage(logs);
        // decode XTokenBridge's event XTokenSent
        (,,,, bytes32 guidId, uint64 nonce,) = BridgeTestLib._extractXTokenSentMessage(logs);
        assertEq(guidId, guidId_, "XTokenSent has correct guid");

        // --------------- Receive message on plasma side
        vm.selectFork(plasma.fork);

        Origin memory origin =
            Origin({srcEid: sonic.endpointId, sender: bytes32(uint(uint160(address(sonic.oapp)))), nonce: nonce});

        vm.prank(plasma.receiveLib);
        ILayerZeroEndpointV2(plasma.endpoint).verify(origin, plasma.oapp, keccak256(abi.encodePacked(guidId_, message)));

        {
            bool isVerifiable = ILayerZeroEndpointV2(plasma.endpoint).verifiable(origin, plasma.oapp);
            require(isVerifiable, "Message not verifiable yet");

            bytes32 inboundPayloadHash = ILayerZeroEndpointV2(plasma.endpoint)
                .inboundPayloadHash(plasma.oapp, sonic.endpointId, bytes32(uint(uint160(address(sonic.oapp)))), nonce);
            assertEq(inboundPayloadHash, keccak256(abi.encodePacked(guidId_, message)));

            uint64 currentInboundNonce = ILayerZeroEndpointV2(plasma.endpoint)
                .inboundNonce(plasma.oapp, sonic.endpointId, bytes32(uint(uint160(address(sonic.oapp)))));
            assertEq(currentInboundNonce, 1, "Inbound nonce should be 1 before lzReceive (and 0 initially)");
        }

        vm.recordLogs();
        vm.prank(plasma.executor);
        ILayerZeroEndpointV2(plasma.endpoint).lzReceive(origin, plasma.oapp, guidId_, message, "");
        (,, bytes memory composeMessage) = BridgeTestLib._extractComposeMessage(vm.getRecordedLogs());

        vm.prank(plasma.endpoint);
        IOAppComposer(plasma.xTokenBridge).lzCompose(plasma.oapp, guidId_, composeMessage, address(0), "");

        assertEq(IERC20(plasma.xToken).balanceOf(address(this)), 1e18, "user should receive 1e18 xToken on plasma");
    }

    //endregion ------------------------------------- Send xToken between chains

    //region ------------------------------------- Unit tests
    function _testSendXToken(
        BridgeTestLib.ChainConfig memory src,
        BridgeTestLib.ChainConfig memory dest,
        uint amount_,
        uint guidId_
    ) internal returns (Results memory r) {
        // --------------- initial state on src
        vm.selectFork(dest.fork);
        r.targetBefore = getBalances(dest, address(this));

        // --------------- send xToken on src
        vm.selectFork(src.fork);
        r.srcBefore = getBalances(src, address(this));

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT_LZRECEIVE, 0)
            .addExecutorLzComposeOption(0, GAS_LIMIT_LZCOMPOSE, 0);
        MessagingFee memory msgFee = IXTokenBridge(src.xTokenBridge).quoteSend(dest.endpointId, amount_, options);

        vm.recordLogs();
        IXTokenBridge(src.xTokenBridge).send{value: msgFee.nativeFee}(dest.endpointId, amount_, msgFee, options);
        (bytes memory message,) = BridgeTestLib._extractSendMessage(vm.getRecordedLogs());

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
        IERC20 stbl = IERC20(IXToken(chain.xToken).token());

        results.balanceUserMainToken = stbl.balanceOf(user);
        results.balanceUserXToken = IERC20(chain.xToken).balanceOf(user);
        results.balanceOappMainToken = stbl.balanceOf(chain.oapp);
        results.balanceXTokenMainToken = stbl.balanceOf(chain.xToken);
        results.balanceUserEther = user.balance;
        results.balanceXTokenBridgedMainToken = stbl.balanceOf(chain.xTokenBridge);
    }

    function createXToken(BridgeTestLib.ChainConfig memory chain) internal returns (address) {
        vm.selectFork(chain.fork);

        Proxy xStakingProxy = new Proxy();
        xStakingProxy.initProxy(address(new XStaking()));

        Proxy xTokenProxy = new Proxy();
        xTokenProxy.initProxy(address(new XToken()));

        XToken(address(xTokenProxy))
            .initialize(
                address(chain.platform),
                chain.oapp,
                address(xStakingProxy),
                address(0), // revenue router is not used in the tests
                "xStability",
                "xSTBL"
            );

        XStaking(address(xStakingProxy)).initialize(address(chain.platform), address(xTokenProxy));

        return address(xTokenProxy);
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
        console.log("balanceUserMainToken", r.balanceUserMainToken);
        console.log("balanceUserXToken", r.balanceUserXToken);
        console.log("balanceOappMainToken", r.balanceOappMainToken);
        console.log("balanceXTokenMainToken", r.balanceXTokenMainToken);
        console.log("balanceUserEther", r.balanceUserEther);
        console.log("balanceXTokenBridgedMainToken", r.balanceXTokenBridgedMainToken);
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

    function _setXTokenBridge(BridgeTestLib.ChainConfig memory chain) internal {
        vm.selectFork(chain.fork);
        vm.prank(chain.multisig);
        IXToken(chain.xToken).setBridge(chain.xTokenBridge, true);
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
        implementations[0] = address(new XToken());

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
