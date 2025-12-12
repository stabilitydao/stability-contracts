// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Script} from "forge-std/Script.sol";
import {XStaking} from "../../src/tokenomics/XStaking.sol";
import {DAO} from "../../src/tokenomics/DAO.sol";
import {XToken} from "../../src/tokenomics/XToken.sol";
import {RevenueRouter} from "../../src/tokenomics/RevenueRouter.sol";
import {Platform} from "../../src/core/Platform.sol";
import {XTokenBridge} from "../../src/tokenomics/XTokenBridge.sol";
import {TokenOFTAdapter} from "../../src/tokenomics/TokenOFTAdapter.sol";
import {BridgedToken} from "../../src/tokenomics/BridgedToken.sol";
import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";

contract PrepareUpgrade25121alpha is Script {
    uint internal constant SONIC_CHAIN_ID = 146;
    uint internal constant PLASMA_CHAIN_ID = 9745;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        if (block.chainid == SONIC_CHAIN_ID) {
            /// XTokenBridge 1.0.1
            new XTokenBridge(SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT);

            /// TokenOFTAdapter 1.0.1
            new TokenOFTAdapter(SonicConstantsLib.TOKEN_STBL, SonicConstantsLib.LAYER_ZERO_V2_ENDPOINT);
        } else if (block.chainid == PLASMA_CHAIN_ID) {
            /// Platform 1.6.4
            new Platform();

            /// XTokenBridge 1.0.1
            new XTokenBridge(PlasmaConstantsLib.LAYER_ZERO_V2_ENDPOINT);

            /// BridgedToken 1.0.2
            new BridgedToken(PlasmaConstantsLib.LAYER_ZERO_V2_ENDPOINT);
        }

        vm.stopBroadcast();
    }

    function testPrepareUpgrade() external {}
}
