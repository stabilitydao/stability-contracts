// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/console.sol";
import {BridgedSTBL} from "../../src/tokenomics/BridgedSTBL.sol";
import {STBLOFTAdapter} from "../../src/tokenomics/STBLOFTAdapter.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Test} from "forge-std/Test.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {AvalancheConstantsLib} from "../../chains/avalanche/AvalancheConstantsLib.sol";
import {SendParam, IOFT} from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import {MessagingFee} from "@layerzerolabs/oapp-evm/contracts/oapp/OAppSender.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Origin} from "@layerzerolabs/oapp-evm/contracts/oapp/interfaces/IOAppReceiver.sol";
import {OFTMsgCodec} from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import {OptionsBuilder} from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

contract BridgedSTBLTest is Test {
    using OptionsBuilder for bytes;

    address public multisigSonic;
    address public multisigAvalanche;

    uint private constant SONIC_FORK_BLOCK = 52228979; // Oct-28-2025 01:14:21 PM +UTC
    uint private constant AVALANCHE_FORK_BLOCK = 71037861; // Oct-28-2025 13:17:17 UTC

    uint internal forkSonic;
    uint internal forkAvalanche;

    STBLOFTAdapter internal adapter;
    BridgedSTBL internal bridgedToken;

    constructor() {
        forkSonic = vm.createFork(vm.envString("SONIC_RPC_URL"), SONIC_FORK_BLOCK);
        forkAvalanche = vm.createFork(vm.envString("AVALANCHE_RPC_URL"), AVALANCHE_FORK_BLOCK);

        // ------------------- Create adapter and bridged token
        bridgedToken = BridgedSTBL(setupSTBLBridgedOnAvalanche());
        adapter = STBLOFTAdapter(setupSTBLOFTAdapterOnSonic());

        // ------------------- Sonic: set up peer connection
        vm.selectFork(forkSonic);
        multisigSonic = IPlatform(SonicConstantsLib.PLATFORM).multisig();

        vm.prank(multisigSonic);
        adapter.setPeer(
            AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            bytes32(uint256(uint160(address(bridgedToken))))
        );

        // ------------------- Avalanche: set up peer connection
        vm.selectFork(forkAvalanche);
        multisigAvalanche = IPlatform(AvalancheConstantsLib.PLATFORM).multisig();

        vm.prank(multisigAvalanche);
        bridgedToken.setPeer(
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            bytes32(uint256(uint160(address(adapter))))
        );
    }

    function testViewSTBLOFTAdapter() public {
        vm.selectFork(forkSonic);

        assertEq(adapter.owner(), multisigSonic);
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
        console.log("1");

        // ------------------- Send
        vm.prank(sender);
        adapter.send{value: msgFee.nativeFee}(sendParam, msgFee, sender);
        console.log("1");

        // ------------------- Check results
        assertEq(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(sender), balance0 - sendAmount, "balance STBL after");
        assertEq(IERC20(SonicConstantsLib.TOKEN_STBL).balanceOf(address(adapter)), sendAmount, "all tokens are in adapter");

        // ------------------ Avalanche: simulate message reception
        vm.selectFork(forkAvalanche);

        console.log("1");
        (bytes memory oftMessage,) = OFTMsgCodec.encode(
            bytes32(uint256(uint160(sender))), // to
            uint64(sendAmount),                        // amountLD
            ""                                 // composeMsg
        );

        console.log("1");
        Origin memory origin = Origin({
            srcEid: SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            sender: bytes32(uint256(uint160(address(adapter)))),
            nonce: 1
        });

        console.log("1");
        vm.prank(AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT);
        bridgedToken.lzReceive(
            origin,
            bytes32(0), // guid
            oftMessage,
            address(0), // executor
            ""          // extraData
        );
        console.log("1");

        assertEq(bridgedToken.balanceOf(address(this)), sendAmount, "user received tokens on Avalanche");
    }

    //region ------------------------------------- Internal logic
    function setupSTBLBridgedOnAvalanche() internal returns (address) {
        vm.selectFork(forkAvalanche);

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new BridgedSTBL(AvalancheConstantsLib.LAYER_ZERO_V2_ENDPOINT)));
        BridgedSTBL stblBridged = BridgedSTBL(address(proxy));
        stblBridged.initialize(address(AvalancheConstantsLib.PLATFORM));

        return address(stblBridged);
    }

    function setupSTBLOFTAdapterOnSonic() internal returns (address) {
        vm.selectFork(forkSonic);

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new STBLOFTAdapter(SonicConstantsLib.TOKEN_STBL, SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT)));
        STBLOFTAdapter stblOFTAdapter = STBLOFTAdapter(address(proxy));
        stblOFTAdapter.initialize(address(SonicConstantsLib.PLATFORM));

        return address(stblOFTAdapter);
    }

    //endregion ------------------------------------- Internal logic
}
