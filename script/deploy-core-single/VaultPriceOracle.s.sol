// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {VaultPriceOracle} from "../../src/core/VaultPriceOracle.sol";

contract DeployVaultPriceOracle is Script {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    uint public constant MIN_QUORUM = 3;
    uint public constant MAX_PRICE_AGE = 1 days;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new VaultPriceOracle()));
        VaultPriceOracle vaultPriceOracle = VaultPriceOracle(address(proxy));
        vaultPriceOracle.initialize(address(PLATFORM));

        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
