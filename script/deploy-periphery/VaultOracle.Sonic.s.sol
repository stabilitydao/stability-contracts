// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script} from "forge-std/Script.sol";
import {VaultOracle} from "../../src/periphery/VaultOracle.sol";

contract DeployFrontendSonic is Script {
    address public constant VAULT_USDC_SCUSD_ISF_USDC = 0xb773B791F3baDB3b28BC7A2da18E2a012b9116c2;
    address public constant VAULT_USDC_SCUSD_ISF_SCUSD = 0x8C64D2a1960C7B4b22Dbb367D2D212A21E75b942;
    address public constant VAULT_USDC_SCUSD_SF = 0xDe708055728F53d557608b13691dAeE5a921B5AF;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        new VaultOracle(VAULT_USDC_SCUSD_ISF_USDC);
        new VaultOracle(VAULT_USDC_SCUSD_ISF_SCUSD);
        new VaultOracle(VAULT_USDC_SCUSD_SF);
        vm.stopBroadcast();
    }

    function testDeployPeriphery() external {}
}
