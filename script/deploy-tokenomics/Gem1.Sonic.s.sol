// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {Token} from "../../src/tokenomics/Token.sol";

contract DeployGem1 is Script {
    address public constant MERKLE_DISTRIBUTOR = 0x0391aBDCFaB86947d93f9dd032955733B639416b;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new Token(MERKLE_DISTRIBUTOR, "Stability Gem Season 1", "sGEM1");
        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
