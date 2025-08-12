// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {MetaVaultFactory} from "../../src/core/MetaVaultFactory.sol";
import {RecoveryToken, IRecoveryToken} from "../../src/core/vaults/RecoveryToken.sol";

contract RecoveryTokenSonicTest is Test {
    uint public constant FORK_BLOCK = 42480655; // Aug-11-2025 07:50:37 AM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public multisig;
    IMetaVaultFactory public metaVaultFactory;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
    }

    function setUp() public {
        multisig = IPlatform(PLATFORM).multisig();
        metaVaultFactory = IMetaVaultFactory(SonicConstantsLib.METAVAULT_FACTORY);

        _upgradePlatform();
        _setupMetaVaultFactory();
    }

    function test_RecoveryToken() public {
        vm.prank(multisig);
        address recToken = metaVaultFactory.deployRecoveryToken(0x00, SonicConstantsLib.METAVAULT_metaUSD);
        assertEq(IRecoveryToken(recToken).target(), SonicConstantsLib.METAVAULT_metaUSD);
    }

    function _upgradePlatform() internal {
        address[] memory proxies = new address[](1);
        proxies[0] = address(metaVaultFactory);

        address[] memory implementations = new address[](1);
        implementations[0] = address(new MetaVaultFactory());

        vm.prank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.08.0-alpha", proxies, implementations);

        skip(1 days);

        vm.prank(multisig);
        IPlatform(PLATFORM).upgrade();
    }

    function _setupMetaVaultFactory() internal {
        address recoveryTokenImplementation = address(new RecoveryToken());
        vm.prank(multisig);
        metaVaultFactory.setRecoveryTokenImplementation(recoveryTokenImplementation);
    }
}
