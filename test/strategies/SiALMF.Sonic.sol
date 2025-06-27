// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../src/core/vaults/MetaVault.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {MetaUsdAdapter} from "../../src/adapters/MetaUsdAdapter.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {UniversalTest} from "../base/UniversalTest.sol";


contract SiloALMFStrategyTest is SonicSetup, UniversalTest {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(34471950); // Jun-17-2025 09:08:37 AM +UTC
        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;
    }

    function testSiALMFSonic() public universalTest {
        _addStrategy(52);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO_ALMF,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }

    function _preDeposit() internal override {
        _upgradeMetaVault(address(PLATFORM), SonicConstantsLib.METAVAULT_metaUSD);

        vm.prank(IPlatform(PLATFORM).multisig());
        IMetaVault(SonicConstantsLib.METAVAULT_metaUSD).changeWhitelist(currentStrategy, true);
    }


    //region --------------------------------------- Helper functions
    function _upgradeMetaVault(address platform, address metaVault_) internal {
        IMetaVaultFactory metaVaultFactory = IMetaVaultFactory(IPlatform(platform).metaVaultFactory());
        address multisig = IPlatform(platform).multisig();

        // Upgrade MetaVault to the new implementation
        address vaultImplementation = address(new MetaVault());
        vm.prank(multisig);
        metaVaultFactory.setMetaVaultImplementation(vaultImplementation);
        address[] memory metaProxies = new address[](1);
        metaProxies[0] = address(metaVault_);
        vm.prank(multisig);
        metaVaultFactory.upgradeMetaProxies(metaProxies);
    }
    //endregion --------------------------------------- Helper functions
}
