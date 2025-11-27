// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {XSTBL} from "../../src/tokenomics/XSTBL.sol";
import {BridgeLib} from "./libs/BridgeLib.sol";
import {console, Test, Vm} from "forge-std/Test.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";
import {XTokenBridge} from "../../src/tokenomics/XTokenBridge.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IXSTBL} from "../../src/interfaces/IXSTBL.sol";
import {IXTokenBridge} from "../../src/interfaces/IXTokenBridge.sol";
import {PacketV1Codec} from "@layerzerolabs/lz-evm-protocol-v2/contracts/messagelib/libs/PacketV1Codec.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StabilityOFTAdapter} from "../../src/tokenomics/StabilityOFTAdapter.sol";
import {BridgedToken} from "../../src/tokenomics/BridgedToken.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {AvalancheConstantsLib} from "../../chains/avalanche/AvalancheConstantsLib.sol";
import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";
import {MessagingFee} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {IOAppReceiver} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";

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

    BridgeLib.ChainConfig internal sonic;
    BridgeLib.ChainConfig internal avalanche;
    BridgeLib.ChainConfig internal plasma;

    struct ChainResults {
        uint balanceUserSTBL;
        uint balanceUserXSTBL;
        uint balanceOappSTBL;
        uint balanceXTokenSTBL;
        uint balanceUserEther;
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

            sonic = BridgeLib.createConfigSonic(vm, forkSonic);
            avalanche = BridgeLib.createConfigAvalanche(vm, forkAvalanche);
            plasma = BridgeLib.createConfigPlasma(vm, forkPlasma);
        }

        // ------------------- Create adapter and bridged token
        adapter = StabilityOFTAdapter(BridgeLib.setupStabilityOFTAdapterOnSonic(vm, sonic));
        bridgedTokenAvalanche = BridgedToken(BridgeLib.setupSTBLBridged(vm, avalanche));
        bridgedTokenPlasma = BridgedToken(BridgeLib.setupSTBLBridged(vm, plasma));

        sonic.oapp = address(adapter);
        avalanche.oapp = address(bridgedTokenAvalanche);
        plasma.oapp = address(bridgedTokenPlasma);

        avalanche.xToken = createXSTBL(avalanche);
        plasma.xToken = createXSTBL(plasma);

        sonic.xTokenBridge = createXTokenBridge(sonic);
        avalanche.xTokenBridge = createXTokenBridge(avalanche);
        plasma.xTokenBridge = createXTokenBridge(plasma);

        // ------------------- Set up STBL-bridges
        BridgeLib.setUpSonicAvalanche(vm, sonic, avalanche);
        BridgeLib.setUpSonicPlasma(vm, sonic, plasma);
        BridgeLib.setUpAvalanchePlasma(vm, avalanche, plasma);

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

        // --------------- mint XSTBL on Sonic
        vm.selectFork(sonic.fork);
        deal(SonicConstantsLib.TOKEN_STBL, address(this), 100e18);

        IERC20(SonicConstantsLib.TOKEN_STBL).approve(sonic.xToken, 100e18);
        IXSTBL(sonic.xToken).enter(100e18);

        // --------------- set up xTokenBridge on Sonic
        vm.prank(sonic.multisig);
        IXTokenBridge(sonic.xTokenBridge).setXTokenBridge(plasma.endpointId, plasma.xTokenBridge);

        // --------------- set up xTokenBridge on Plasma
        vm.selectFork(plasma.fork);

        vm.prank(plasma.multisig);
        IXTokenBridge(plasma.xTokenBridge).setXTokenBridge(sonic.endpointId, sonic.xTokenBridge);

        r.targetBefore = getBalances(plasma, address(this));

        // --------------- send XSTBL on Sonic
        vm.selectFork(sonic.fork);
        r.srcBefore = getBalances(sonic, address(this));

        console.log("1");
        bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(GAS_LIMIT, 0);
        MessagingFee memory msgFee = IXTokenBridge(sonic.xTokenBridge).quoteSend(
            plasma.endpointId,
            50e18,
            options,
            false
        );

        console.log("1");
        vm.recordLogs();
        IXTokenBridge(sonic.xTokenBridge).send{value: msgFee.nativeFee}(
            plasma.endpointId,
            50e18,
            msgFee,
            options
        );
        console.log("1");
        bytes memory message = BridgeLib._extractSendMessage(vm.getRecordedLogs());

        // --------------- Simulate message receiving on Plasma
        vm.selectFork(plasma.fork);

        Origin memory origin = Origin({
            srcEid: SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            sender: bytes32(uint(uint160(address(sonic.oapp)))),
            nonce: 1
        });

        {
            uint gasBefore = gasleft();
            vm.prank(plasma.endpoint);
            IOAppReceiver(plasma.oapp).lzReceive(
                origin,
                bytes32(0), // guid: actual value doesn't matter
                message,
                address(0), // executor
                "" // extraData
            );
            assertLt(gasBefore - gasleft(), GAS_LIMIT, "gas limit exceeded");
            console.log("gasBefore - gasleft()", gasBefore - gasleft());
        }

        r.targetAfter = getBalances(plasma, address(this));

        // --------------- Sonic
        vm.selectFork(sonic.fork);
        r.srcAfter = getBalances(sonic, address(this));

        // --------------- Verify results
        // todo
        showResults(r);

    }

    //endregion ------------------------------------- Send XSTBL between chains


    //region ------------------------------------- Internal utils
    function getBalances(BridgeLib.ChainConfig memory chain, address user) internal view returns (ChainResults memory results) {
        IERC20 stbl = IERC20(IXSTBL(chain.xToken).STBL());

        results.balanceUserSTBL = stbl.balanceOf(user);
        results.balanceUserXSTBL = IERC20(chain.xToken).balanceOf(user);
        results.balanceOappSTBL = stbl.balanceOf(chain.oapp);
        results.balanceXTokenSTBL = stbl.balanceOf(chain.xToken);
        results.balanceUserEther = user.balance;
    }

    function createXSTBL(BridgeLib.ChainConfig memory chain) internal returns (address) {
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

    function createXTokenBridge(BridgeLib.ChainConfig memory chain) internal returns (address) {
        vm.selectFork(chain.fork);

        Proxy xTokenBridgeProxy = new Proxy();
        xTokenBridgeProxy.initProxy(address(new XTokenBridge()));

        XTokenBridge(address(xTokenBridgeProxy)).initialize(address(chain.platform), chain.oapp, chain.xToken);

        return address(xTokenBridgeProxy);
    }

    function showResults(Results memory r) internal {
        showChainResults("src.before", r.srcBefore);
        showChainResults("target.before", r.targetBefore);
        showChainResults("src.after", r.srcAfter);
        showChainResults("target.before", r.targetAfter);
    }

    function showChainResults(string memory label, ChainResults memory r) internal view {
        console.log("------------------ %s ------------------", label);
        console.log("balanceUserSTBL", r.balanceUserSTBL);
        console.log("balanceUserXSTBL", r.balanceUserXSTBL);
        console.log("balanceOappSTBL", r.balanceOappSTBL);
        console.log("balanceXTokenSTBL", r.balanceXTokenSTBL);
        console.log("balanceUserEther", r.balanceUserEther);
    }

    //endregion ------------------------------------- Internal utils
}