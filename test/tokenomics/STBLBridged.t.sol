// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {STBLBridged} from "../../src/tokenomics/STBLBridged.sol";
import {STBLOFTAdapter} from "../../src/tokenomics/STBLOFTAdapter.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Test} from "forge-std/Test.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {console} from "forge-std/console.sol";
import {AvalancheConstantsLib} from "../../chains/avalanche/AvalancheConstantsLib.sol";

contract STBLBridgedTest is Test {
    address public multisig;

    uint private constant SONIC_FORK_BLOCK = 52228979; // Oct-28-2025 01:14:21 PM +UTC
    uint private constant AVALANCHE_FORK_BLOCK = 71037861; // Oct-28-2025 13:17:17 UTC

    /// @dev https://docs.layerzero.network/v2/deployments/deployed-contracts
    address private constant ENDPOINT_V2_AVALANCHE = 0x1a44076050125825900e736c501f859c50fE728c; // todo to constants lib
    address private constant ENDPOINT_V2_SONIC = 0x6F475642a6e85809B1c36Fa62763669b1b48DD5B;

    uint internal forkSonic;
    uint internal forkAvalanche;

    constructor() {
        forkSonic = vm.createFork(vm.envString("SONIC_RPC_URL"), SONIC_FORK_BLOCK);
        forkAvalanche = vm.createFork(vm.envString("AVALANCHE_RPC_URL"), AVALANCHE_FORK_BLOCK);

        vm.selectFork(forkSonic);
        multisig = IPlatform(SonicConstantsLib.PLATFORM).multisig();
    }

    function testInit() public pure {
        console.logBytes32(
            keccak256(abi.encode(uint(keccak256("erc7201:stability.STBLBridged")) - 1)) & ~bytes32(uint(0xff))
        );
    }

    function testBridge() public {
        address stblAvalanche = setupSTBLBridgedOnAvalanche();
        address adapter = setupSTBLOFTAdapterOnSonic();

        // todo
        // STBLBridged(adapter).send();
    }

    //region ------------------------------------- Internal logic
    function setupSTBLBridgedOnAvalanche() internal returns (address) {
        vm.selectFork(forkAvalanche);

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new STBLBridged(ENDPOINT_V2_AVALANCHE)));
        STBLBridged stblBridged = STBLBridged(address(proxy));
        stblBridged.initialize(address(AvalancheConstantsLib.PLATFORM), "STBL Bridged", "STBLb");

        return address(stblBridged);
    }

    function setupSTBLOFTAdapterOnSonic() internal returns (address) {
        vm.selectFork(forkSonic);

        Proxy proxy = new Proxy();
        proxy.initProxy(address(new STBLOFTAdapter(SonicConstantsLib.TOKEN_STBL, ENDPOINT_V2_SONIC)));
        STBLOFTAdapter stblOFTAdapter = STBLOFTAdapter(address(proxy));
        stblOFTAdapter.initialize(address(SonicConstantsLib.PLATFORM));

        return address(stblOFTAdapter);
    }

    //endregion ------------------------------------- Internal logic
}
