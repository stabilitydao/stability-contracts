// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {StdConfig} from "forge-std/StdConfig.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {Variable, LibVariable} from "forge-std/LibVariable.sol";
import {Test} from "forge-std/Test.sol";
import {BridgeTestLib} from "../tokenomics/libs/BridgeTestLib.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";
import {IPriceAggregatorOApp} from "../../src/interfaces/IPriceAggregatorOApp.sol";

// todo
contract PriceAggregatorOAppSetupTest is Test {
    uint private constant SONIC_FORK_BLOCK = 52228979; // Oct-28-2025 01:14:21 PM +UTC
    uint private constant PLASMA_FORK_BLOCK = 5398928; // Nov-5-2025 07:38:59 UTC

    using LibVariable for Variable;

    BridgeTestLib.ChainConfig internal sonic;
    BridgeTestLib.ChainConfig internal plasma;

    constructor() {
        uint forkSonic = vm.createFork(vm.envString("SONIC_RPC_URL"), SONIC_FORK_BLOCK);
        uint forkPlasma = vm.createFork(vm.envString("PLASMA_RPC_URL"), PLASMA_FORK_BLOCK);

        StdConfig configDeployed = new StdConfig("./config.d.toml", false);

        //        sonic = _createConfigSonic(forkSonic, configDeployed);
        //        plasma = _createConfigPlasma(forkPlasma, configDeployed);
    }

    //    function testSetup() public {
    //        // ------------------------------- setup bridges between Sonic and Plasma
    //        BridgeTestLib.setUpSonicPlasma(vm, sonic, plasma);
    //
    //        // ------------------------------- whitelist price updater on Sonic
    //        vm.selectFork(sonic.fork);
    //        address priceUpdater = makeAddr("Price updater");
    //
    //        vm.prank(sonic.multisig);
    //        IPriceAggregatorOApp(sonic.oapp).changeWhitelist(priceUpdater, true);
    //    }
    //
    //    function _createConfigSonic(
    //        uint forkId,
    //        StdConfig configDeployed
    //    ) internal returns (BridgeTestLib.ChainConfig memory) {
    //        vm.selectFork(forkId);
    //
    //        address oapp = configDeployed.get("PRICE_AGGREGATOR_OAPP_STBL").toAddress();
    //        require(oapp != address(0), "Price aggregator is not deployed on Sonic");
    //
    //        address xToken = configDeployed.get("XSTBL").toAddress();
    //        require(xToken != address(0), "XSTBL is not deployed on Sonic");
    //
    //        address xTokenBridge = configDeployed.get("XTokenBridge").toAddress();
    //        require(xTokenBridge != address(0), "XTokenBridge is not deployed on Sonic");
    //
    //        return BridgeTestLib.ChainConfig({
    //            fork: forkId,
    //            multisig: IPlatform(SonicConstantsLib.PLATFORM).multisig(),
    //            oapp: oapp,
    //            endpointId: SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
    //            endpoint: SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT,
    //            sendLib: SonicConstantsLib.LAYER_ZERO_V2_SEND_ULN_302,
    //            receiveLib: SonicConstantsLib.LAYER_ZERO_V2_RECEIVE_ULN_302,
    //            platform: SonicConstantsLib.PLATFORM,
    //            executor: SonicConstantsLib.LAYER_ZERO_V2_EXECUTOR,
    //            xToken: xToken,
    //            xTokenBridge: xTokenBridge
    //        });
    //    }
    //
    //    function _createConfigPlasma(
    //        uint forkId,
    //        StdConfig configDeployed
    //    ) internal returns (BridgeTestLib.ChainConfig memory) {
    //        vm.selectFork(forkId);
    //
    //        address oapp = configDeployed.get("BRIDGED_PRICE_ORACLE_STBL").toAddress();
    //        require(oapp != address(0), "Price aggregator is not deployed on Plasma");
    //
    //        address xToken = configDeployed.get("XSTBL").toAddress();
    //        require(xToken != address(0), "XSTBL is not deployed on Plasma");
    //
    //        address xTokenBridge = configDeployed.get("XTokenBridge").toAddress();
    //        require(xTokenBridge != address(0), "XTokenBridge is not deployed on Plasma");
    //
    //        return BridgeTestLib.ChainConfig({
    //            fork: forkId,
    //            multisig: IPlatform(PlasmaConstantsLib.PLATFORM).multisig(),
    //            oapp: address(0), // to be set later
    //            endpointId: PlasmaConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
    //            endpoint: PlasmaConstantsLib.LAYER_ZERO_V2_ENDPOINT,
    //            sendLib: PlasmaConstantsLib.LAYER_ZERO_V2_SEND_ULN_302,
    //            receiveLib: PlasmaConstantsLib.LAYER_ZERO_V2_RECEIVE_ULN_302,
    //            platform: PlasmaConstantsLib.PLATFORM,
    //            executor: PlasmaConstantsLib.LAYER_ZERO_V2_EXECUTOR,
    //            xToken: address(0),
    //            xTokenBridge: address(0)
    //        });
    //    }
}
