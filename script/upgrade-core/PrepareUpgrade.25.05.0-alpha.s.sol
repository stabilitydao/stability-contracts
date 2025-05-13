// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {Platform} from "../../src/core/Platform.sol";
import {PriceReader} from "../../src/core/PriceReader.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {MetaVaultFactory} from "../../src/core/MetaVaultFactory.sol";
import {FeeTreasury} from "../../src/tokenomics/FeeTreasury.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";

contract PrepareUpgrade11 is Script {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // CVault 1.6.0: IStabilityVault
        //        new CVault();

        // Platform 1.4.0: IPlatform.metaVaultFactory()
        //        new Platform();

        // PriceReader 1.1.0: IPriceReader.getVaultPrice; IPriceReader.vaultsWithSafeSharePrice
        //        new PriceReader();

        // FeeTreasury 1.1.0: assets, harvest, fixes
        //        new FeeTreasury();

        // MetaVaultFactory 1.0.0
        //        new MetaVaultFactory();
        Proxy proxy = new Proxy();
        proxy.initProxy(0x8edF2A8B981757cFa58Ba163b82A877f09D9C830);
        MetaVaultFactory(address(proxy)).initialize(PLATFORM);
        vm.stopBroadcast();
    }

    function testPrepareUpgrade() external {}
}
