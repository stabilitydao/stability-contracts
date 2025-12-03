// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Script} from "forge-std/Script.sol";
import {DAO} from "../../src/tokenomics/DAO.sol";

contract PrepareUpgrade25105alpha is Script {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // StabilityDAO 1.0.1
        new DAO();

        vm.stopBroadcast();
    }

    function testPrepareUpgrade() external {}
}
