// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {StdConfig} from "forge-std/StdConfig.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {Variable, LibVariable} from "forge-std/LibVariable.sol";
import {Test} from "forge-std/Test.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";
import {BridgeTestLib} from "../../test/tokenomics/libs/BridgeTestLib.sol"; // todo

contract TokenOFTAdapterSonicSetupScript is Test {
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

        require(block.chainid == SONIC_CHAIN_ID, "TokenOFTAdapter is deployed on Sonic only");

        // ---------------------- Initialize
        // StdConfig config = new StdConfig("./config.toml", false);
        StdConfig configDeployed = new StdConfig("./config.d.toml", false);

        BridgeTestLib.ChainConfig memory sonic = _createConfigSonic(configDeployed, delegator);

        // ---------------------- Setup
        vm.startBroadcast(deployerPrivateKey);

        address[] memory requiredDVNs = new address[](2);
        requiredDVNs[0] = SonicConstantsLib.SONIC_DVN_LAYER_ZERO_PUSH;
        requiredDVNs[1] = SonicConstantsLib.SONIC_DVN_HORIZEN_PUSH;

        BridgeTestLib._setupOAppOnChain(
            sonic,
            PlasmaConstantsLib.LAYER_ZERO_V2_ENDPOINT_ID,
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
    ) internal view returns (BridgeTestLib.ChainConfig memory) {
        require(
            uint(configDeployed.get(SONIC_CHAIN_ID, "OAPP_MAIN_TOKEN").ty.kind) != 0,
            "TokenOFTAdapter is not deployed on Sonic"
        );
        address oapp = configDeployed.get(SONIC_CHAIN_ID, "OAPP_MAIN_TOKEN").toAddress();

        require(uint(configDeployed.get(SONIC_CHAIN_ID, "xToken").ty.kind) != 0, "xToken is not deployed on Sonic");
        address xToken = configDeployed.get(SONIC_CHAIN_ID, "xToken").toAddress();

        //        require(uint(configDeployed.get(SONIC_CHAIN_ID, "XTokenBridge").ty.kind) != 0, "XTokenBridge is not deployed on Sonic");
        //        address xTokenBridge = configDeployed.get(SONIC_CHAIN_ID, "XTokenBridge").toAddress();

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
            xTokenBridge: address(0), // xTokenBridge, // not required here
            delegator: delegator_
        });
    }
}
