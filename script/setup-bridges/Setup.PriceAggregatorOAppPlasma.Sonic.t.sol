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
import {BridgeTestLib} from "../../test/tokenomics/libs/BridgeTestLib.sol";

contract PriceAggregatorOAppPlasmaSetupSonicScript is Test {
    using LibVariable for Variable;

    uint internal constant SONIC_CHAIN_ID = 146;
    uint internal constant PLASMA_CHAIN_ID = 9745;

    /// @dev Minimum block confirmations to wait on Sonic
    uint64 internal constant MIN_BLOCK_CONFIRMATIONS_SEND_SONIC = 15;

    /// @dev Minimum block confirmations required on Sonic
    uint64 internal constant MIN_BLOCK_CONFIRMATIONS_RECEIVE_SONIC = 10;

    uint32 internal constant MAX_MESSAGE_SIZE = 256;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address delegator = vm.envAddress("LZ_DELEGATOR");
        require(delegator != address(0), "delegator is not set");

        require(block.chainid == SONIC_CHAIN_ID, "PriceAggregatorOApp is deployed on Sonic only");

        // ---------------------- Initialize
        StdConfig config = new StdConfig("./config.toml", false);
        StdConfig configDeployed = new StdConfig("./config.d.toml", false);

        BridgeTestLib.ChainConfig memory sonic = _createConfigSonic(configDeployed, delegator);
        BridgeTestLib.ChainConfig memory plasma = _createConfigPlasma(configDeployed, delegator);

        // ---------------------- Setup
        vm.startBroadcast(deployerPrivateKey);

        address[] memory requiredDVNs = new address[](1);
        requiredDVNs[0] = BridgeTestLib.SONIC_DVN_LAYER_ZERO_PUSH;

        BridgeTestLib._setupOAppOnChain(
            sonic,
            plasma,
            requiredDVNs,
            MIN_BLOCK_CONFIRMATIONS_SEND_SONIC,
            MAX_MESSAGE_SIZE,
            MIN_BLOCK_CONFIRMATIONS_RECEIVE_SONIC
        );

        vm.stopBroadcast();
    }

    function testDeployScript() external {}

    function _createConfigSonic(
        StdConfig configDeployed,
        address delegator_
    ) internal returns (BridgeTestLib.ChainConfig memory) {
        address oapp = configDeployed.get(SONIC_CHAIN_ID, "PRICE_AGGREGATOR_OAPP_STBL").toAddress();
        require(oapp != address(0), "Price aggregator is not deployed on Sonic");

        address xToken = configDeployed.get(SONIC_CHAIN_ID, "XSTBL").toAddress();
        require(xToken != address(0), "XSTBL is not deployed on Sonic");

        address xTokenBridge = configDeployed.get(SONIC_CHAIN_ID, "XTokenBridge").toAddress();
        require(xTokenBridge != address(0), "XTokenBridge is not deployed on Sonic");

        return BridgeTestLib.ChainConfig({
            fork: 0,
            multisig: IPlatform(SonicConstantsLib.PLATFORM).multisig(),
            oapp: oapp,
            endpointId: SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            endpoint: SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            sendLib: SonicConstantsLib.LAYER_ZERO_V2_SEND_ULN_302,
            receiveLib: SonicConstantsLib.LAYER_ZERO_V2_RECEIVE_ULN_302,
            platform: SonicConstantsLib.PLATFORM,
            executor: SonicConstantsLib.LAYER_ZERO_V2_EXECUTOR,
            xToken: xToken,
            xTokenBridge: xTokenBridge,
            delegator: delegator_
        });
    }

    function _createConfigPlasma(
        StdConfig configDeployed,
        address delegator_
    ) internal returns (BridgeTestLib.ChainConfig memory) {
        address oapp = configDeployed.get(PLASMA_CHAIN_ID, "BRIDGED_PRICE_ORACLE_STBL").toAddress();
        require(oapp != address(0), "Price aggregator is not deployed on Plasma");

        address xToken = configDeployed.get(PLASMA_CHAIN_ID, "XSTBL").toAddress();
        require(xToken != address(0), "XSTBL is not deployed on Plasma");

        address xTokenBridge = configDeployed.get(PLASMA_CHAIN_ID, "XTokenBridge").toAddress();
        require(xTokenBridge != address(0), "XTokenBridge is not deployed on Plasma");

        return BridgeTestLib.ChainConfig({
            fork: 0,
            multisig: IPlatform(PlasmaConstantsLib.PLATFORM).multisig(),
            oapp: oapp,
            endpointId: PlasmaConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            endpoint: PlasmaConstantsLib.LAYER_ZERO_V2_ENDPOINT,
            sendLib: PlasmaConstantsLib.LAYER_ZERO_V2_SEND_ULN_302,
            receiveLib: PlasmaConstantsLib.LAYER_ZERO_V2_RECEIVE_ULN_302,
            platform: PlasmaConstantsLib.PLATFORM,
            executor: PlasmaConstantsLib.LAYER_ZERO_V2_EXECUTOR,
            xToken: xToken,
            xTokenBridge: xTokenBridge,
            delegator: delegator_
        });
    }
}
