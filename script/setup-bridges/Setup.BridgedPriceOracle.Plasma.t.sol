// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {StdConfig} from "forge-std/StdConfig.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {Variable, LibVariable} from "forge-std/LibVariable.sol";
import {Test} from "forge-std/Test.sol";
import {BridgeTestLib} from "../../test/tokenomics/libs/BridgeTestLib.sol"; // todo
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";

contract BridgedPriceOracleSetupPlasmaScript is Test {
    using LibVariable for Variable;

    uint internal constant SONIC_CHAIN_ID = 146;
    uint internal constant PLASMA_CHAIN_ID = 9745;

    /// @dev Minimum block confirmations to wait on Avalanche
    uint64 internal constant MIN_BLOCK_CONFIRMATIONS_SEND_TARGET = 15;

    /// @dev Minimum block confirmations required on Avalanche
    uint64 internal constant MIN_BLOCK_CONFIRMATIONS_RECEIVE_TARGET = 10;

    uint32 internal constant MAX_MESSAGE_SIZE = 256;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address delegator = vm.envAddress("LZ_DELEGATOR");
        require(delegator != address(0), "delegator is not set");

        require(block.chainid == PLASMA_CHAIN_ID, "This script is configured for Plasma only");

        // ---------------------- Initialize
        // StdConfig config = new StdConfig("./config.toml", false);
        StdConfig configDeployed = new StdConfig("./config.d.toml", false);

        BridgeTestLib.ChainConfig memory plasma = _createConfigPlasma(configDeployed, delegator);

        // ---------------------- Setup
        vm.startBroadcast(deployerPrivateKey);

        address[] memory requiredDVNs = new address[](2);
        requiredDVNs[0] = PlasmaConstantsLib.PLASMA_DVN_LAYER_ZERO_PUSH;
        requiredDVNs[1] = PlasmaConstantsLib.PLASMA_DVN_NETHERMIND_PUSH;
        //        requiredDVNs[2] = PLASMA_DVN_HORIZON;

        BridgeTestLib._setupOAppOnChain(
            plasma,
            SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
            requiredDVNs,
            MIN_BLOCK_CONFIRMATIONS_SEND_TARGET,
            MAX_MESSAGE_SIZE,
            MIN_BLOCK_CONFIRMATIONS_RECEIVE_TARGET
        );

        vm.stopBroadcast();
    }

    function testDeployScript() external {}

    function _createConfigPlasma(
        StdConfig configDeployed,
        address delegator_
    ) internal view returns (BridgeTestLib.ChainConfig memory) {
        require(uint(configDeployed.get(PLASMA_CHAIN_ID, "BRIDGED_PRICE_ORACLE_MAIN_TOKEN").ty.kind) != 0 , "Price aggregator is not deployed on Plasma");
        address oapp = configDeployed.get(PLASMA_CHAIN_ID, "BRIDGED_PRICE_ORACLE_MAIN_TOKEN").toAddress();

// we don't use following data in thi script
//        require(uint(configDeployed.get(PLASMA_CHAIN_ID, "xToken").ty.kind) != 0, "xToken is not deployed on Plasma");
//        address xToken = configDeployed.get(PLASMA_CHAIN_ID, "xToken").toAddress();
//
//        require(uint(configDeployed.get(PLASMA_CHAIN_ID, "XTokenBridge").ty.kind) != 0, "XTokenBridge is not deployed on Plasma");
//        address xTokenBridge = configDeployed.get(PLASMA_CHAIN_ID, "XTokenBridge").toAddress();

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
            xToken: address(0), // xToken,
            xTokenBridge: address(0), // xTokenBridge,
            delegator: delegator_
        });
    }
}
