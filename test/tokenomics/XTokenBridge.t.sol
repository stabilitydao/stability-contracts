// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {XSTBL} from "../../src/tokenomics/XSTBL.sol";
import {BridgeTestLib} from "./libs/BridgeTestLib.sol";
import {console, Test} from "forge-std/Test.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";
import {XTokenBridge} from "../../src/tokenomics/XTokenBridge.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {IXSTBL} from "../../src/interfaces/IXSTBL.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IXTokenBridge} from "../../src/interfaces/IXTokenBridge.sol";
import {PacketV1Codec} from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StabilityOFTAdapter} from "../../src/tokenomics/StabilityOFTAdapter.sol";
import {BridgedToken} from "../../src/tokenomics/BridgedToken.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
//import {AvalancheConstantsLib} from "../../chains/avalanche/AvalancheConstantsLib.sol";
//import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";
import {MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {IOAppReceiver} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";
import { IOAppComposer } from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppComposer.sol";

contract XTokenBridgeTest is Test {
    using OptionsBuilder for bytes;
    using PacketV1Codec for bytes;
    using SafeERC20 for IERC20;

    //region ------------------------------------- Constants, data types, variables
    uint private constant SONIC_FORK_BLOCK = 52228979; // Oct-28-2025 01:14:21 PM +UTC
    uint private constant AVALANCHE_FORK_BLOCK = 71037861; // Oct-28-2025 13:17:17 UTC
    uint private constant PLASMA_FORK_BLOCK = 5398928; // Nov-5-2025 07:38:59 UTC

    /// @dev Gas limit for executor lzReceive calls
    uint128 private constant GAS_LIMIT = 100_000;

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

        _setXTokenBridge(sonic, avalanche, plasma);
        _setXTokenBridge(avalanche, sonic, plasma);
        _setXTokenBridge(plasma, sonic, avalanche);

        _setXSTBLBridge(sonic);
        _setXSTBLBridge(avalanche);
        _setXSTBLBridge(plasma);

        // ------------------- Set up STBL-bridges
        BridgeTestLib.setUpSonicAvalanche(vm, sonic, avalanche);
        BridgeTestLib.setUpSonicPlasma(vm, sonic, plasma);
        BridgeTestLib.setUpAvalanchePlasma(vm, avalanche, plasma);

        // ------------------- Provide ether to address(this) to be able to pay fees
        vm.selectFork(sonic.fork);
        deal(address(this), 1 ether);

        vm.selectFork(plasma.fork);
        deal(address(this), 1 ether);

        vm.selectFork(avalanche.fork);
        deal(address(this), 1 ether);
    }
    //endregion ------------------------------------- Constructor

    //region ------------------------------------- Unit tests
    // todo

    //endregion ------------------------------------- Unit tests

    //region ------------------------------------- Send XSTBL between chains
    function testSendXSTBLFromSonicToPlasma() public {
        Results memory r;

        // --------------- initial state on plasma
        vm.selectFork(plasma.fork);
        r.targetBefore = getBalances(plasma, address(this));

        // --------------- mint XSTBL on Sonic
        vm.selectFork(sonic.fork);
        deal(SonicConstantsLib.TOKEN_STBL, address(this), 100e18);

        IERC20(SonicConstantsLib.TOKEN_STBL).approve(sonic.xToken, 100e18);
        IXSTBL(sonic.xToken).enter(100e18);

        // --------------- send XSTBL on Sonic
        vm.selectFork(sonic.fork);
        r.srcBefore = getBalances(sonic, address(this));

        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT, 0);
        MessagingFee memory msgFee = IXTokenBridge(sonic.xTokenBridge).quoteSend(
            plasma.endpointId,
            70e18,
            options,
            false
        );

        vm.recordLogs();
        IXTokenBridge(sonic.xTokenBridge).send{value: msgFee.nativeFee}(
            plasma.endpointId,
            70e18,
            msgFee,
            options
        );
        bytes memory message = BridgeTestLib._extractSendMessage(vm.getRecordedLogs());

        // --------------- Simulate message receiving on Plasma
        vm.selectFork(plasma.fork);

        Origin memory origin = Origin({
            srcEid: SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            sender: bytes32(uint(uint160(address(sonic.oapp)))),
            nonce: 1
        });

        console.log("lzReceive");
        {
            uint gasBefore = gasleft();
            vm.recordLogs();
            vm.prank(plasma.endpoint);
            IOAppReceiver(plasma.oapp).lzReceive(
                origin,
                bytes32(0), // guid: actual value doesn't matter
                message,
                address(0), // executor
                "" // extraData
            );
            assertLt(gasBefore - gasleft(), GAS_LIMIT, "lzReceive gas limit exceeded");
            console.log("gasBefore - gasleft() (lzReceive):", gasBefore - gasleft());
        }
        {
            bytes memory composeMessage = BridgeTestLib._extractComposeMessage(vm.getRecordedLogs());
            uint gasBefore = gasleft();
            vm.recordLogs();
            vm.prank(plasma.endpoint);
            IOAppComposer(plasma.xTokenBridge).lzCompose(
                plasma.oapp,
                bytes32(0), // guid: actual value doesn't matter
                composeMessage,
                address(0), // executor
                "" // extraData
            );
            assertLt(gasBefore - gasleft(), GAS_LIMIT, "lzCompoze gas limit exceeded");
            console.log("gasBefore - gasleft() (compose):", gasBefore - gasleft());
        }

        // see comment from OFTCore:
        // @dev Stores the lzCompose payload that will be executed in a separate tx.
        // Standardizes functionality for executing arbitrary contract invocation on some non-evm chains.
        // @dev The off-chain executor will listen and process the msg based on the src-chain-callers compose options passed.
        // @dev The index is used when a OApp needs to compose multiple msgs on lzReceive.
        // For default OFT implementation there is only 1 compose msg per lzReceive, thus its always 0.
        // endpoint.sendCompose(toAddress, _guid, 0 /* the index of the composed message*/, composeMsg);
        // interface IMessagingComposer {
        // event ComposeSent(address from, address to, bytes32 guid, uint16 index, bytes message);



        r.targetAfter = getBalances(plasma, address(this));

        // --------------- Sonic
        vm.selectFork(sonic.fork);
        r.srcAfter = getBalances(sonic, address(this));

        // --------------- Verify results
        // todo
        showResults(r);

        console.log("user", address(this));
        console.log("sonic.xToken", sonic.xToken);
        console.log("sonic.oapp", sonic.oapp);
        console.log("sonic.xTokenBridge", sonic.xTokenBridge);
        console.log("sonic.STBL", IXSTBL(sonic.xToken).STBL());

        vm.selectFork(plasma.fork);
        console.log("plasma.xToken", plasma.xToken);
        console.log("plasma.oapp", plasma.oapp);
        console.log("plasma.xTokenBridge", plasma.xTokenBridge);
        console.log("plasma.STBL", IXSTBL(plasma.xToken).STBL());
    }

    //endregion ------------------------------------- Send XSTBL between chains


    //region ------------------------------------- Internal utils
    function getBalances(BridgeTestLib.ChainConfig memory chain, address user) internal view returns (ChainResults memory results) {
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

        XSTBL(address(xSTBLProxy)).initialize(
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
    //region ------------------------------------- Helpers
}