// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {VaultPriceOracle} from "../../src/core/VaultPriceOracle.sol";

contract DeployVaultPriceOracle is Script {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    uint public constant MIN_QUORUM = 3;
    uint public constant MAX_PRICE_AGE = 1 days;
    address[] public validators = [
        0x754341F215cBc80D8548b853Fd1F60C3FDaE6B26 // TODO remove test adr
    ];
    address[] public vaults = [
        0x7bCEc157a1d10f00391e9E782de5998fABCc1aA7 // Credix USDC
    ];

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new VaultPriceOracle()));
        VaultPriceOracle vaultPriceOracle = VaultPriceOracle(address(proxy));
        vaultPriceOracle.initialize(address(PLATFORM), MIN_QUORUM, validators, vaults, MAX_PRICE_AGE);

        vm.stopBroadcast();
    }

    function testDeployScript() external {}
}
