// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Platform} from "../../src/core/Platform.sol";
import {PriceReader} from "../../src/core/PriceReader.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {MetaVaultFactory} from "../../src/core/MetaVaultFactory.sol";
import {FeeTreasury} from "../../src/tokenomics/FeeTreasury.sol";

contract PrepareUpgrade11 is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // CVault 1.6.0: IStabilityVault
        new CVault();

        // Platform 1.4.0: IPlatform.metaVaultFactory()
        new Platform();

        // PriceReader 1.1.0: IPriceReader.getVaultPrice; IPriceReader.vaultsWithSafeSharePrice
        new PriceReader();

        // FeeTreasury 1.1.0: assets, harvest, fixes
        new FeeTreasury();

        // MetaVaultFactory 1.0.0
        new MetaVaultFactory();

        vm.stopBroadcast();
    }

    function testPrepareUpgrade() external {}
}
