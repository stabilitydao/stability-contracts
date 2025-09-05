// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MetaVault, IMetaVault, IStabilityVault} from "../../src/core/vaults/MetaVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";

/// @dev MetaVault 1.2.0
contract MetaVaultSonicUpgrade2 is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVault public metaVault;
    IMetaVaultFactory public metaVaultFactory;
    address public multisig;

    constructor() {
        // May-19-2025 09:53:57 AM +UTC
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), 27965000));
        metaVault = IMetaVault(SonicConstantsLib.METAVAULT_metaUSD);
        metaVaultFactory = IMetaVaultFactory(IPlatform(PLATFORM).metaVaultFactory());
        multisig = IPlatform(PLATFORM).multisig();
    }

    function testMetaVaultVaultUpgrade2() public {
        uint[] memory newProportions = new uint[](2);
        newProportions[0] = 7e17;
        newProportions[1] = 3e17;
        vm.prank(multisig);
        vm.expectRevert(IStabilityVault.NotSupported.selector);
        metaVault.addVault(SonicConstantsLib.METAVAULT_metascUSD, newProportions);

        // deploy new impl and upgrade
        address vaultImplementation = address(new MetaVault());
        vm.prank(multisig);
        metaVaultFactory.setMetaVaultImplementation(vaultImplementation);
        address[] memory metaProxies = new address[](1);
        metaProxies[0] = address(metaVault);
        vm.prank(multisig);
        metaVaultFactory.upgradeMetaProxies(metaProxies);

        vm.prank(multisig);
        metaVault.addVault(SonicConstantsLib.METAVAULT_metascUSD, newProportions);

        assertEq(metaVault.vaults().length, 2);
        assertEq(metaVault.currentProportions()[1], 0);
        assertEq(metaVault.targetProportions()[1], 3e17);
    }
}
