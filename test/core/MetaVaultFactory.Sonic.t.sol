// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console, Vm} from "forge-std/Test.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {Platform} from "../../src/core/Platform.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {MetaVaultFactory, IMetaVaultFactory, IControllable} from "../../src/core/MetaVaultFactory.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";

contract MetaVaultFactoryTest is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVaultFactory public metaVaultFactory;
    address public multisig;

    constructor() {
        // May-10-2025 10:38:26 AM +UTC
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), 25729900));
    }

    function setUp() public {
        multisig = IPlatform(PLATFORM).multisig();

        _deployMetaVaultFactory();
        _upgradePlatform();
        _setupMetaVaultFactory();
        _setupImplementations();

        // console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.MetaVaultFactory")) - 1)) & ~bytes32(uint256(0xff)));
    }

    function test_MetaVaultFactory_deployment() public view {
        assertNotEq(metaVaultFactory.metaVaultImplementation(), address(0));
    }

    function _upgradePlatform() internal {
        address[] memory proxies = new address[](1);
        proxies[0] = PLATFORM;
        address[] memory implementations = new address[](1);
        implementations[0] = address(new Platform());
        vm.startPrank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.05.0-alpha", proxies, implementations);
        skip(1 days);
        IPlatform(PLATFORM).upgrade();
        vm.stopPrank();
    }

    function _setupMetaVaultFactory() internal {
        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        Platform(PLATFORM).setupMetaVaultFactory(address(metaVaultFactory));
        vm.prank(multisig);
        Platform(PLATFORM).setupMetaVaultFactory(address(metaVaultFactory));
        assertEq(IPlatform(PLATFORM).metaVaultFactory(), address(metaVaultFactory));
    }

    function _deployMetaVaultFactory() internal {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new MetaVaultFactory()));
        metaVaultFactory = IMetaVaultFactory(address(proxy));
        metaVaultFactory.initialize(PLATFORM);
    }

    function _setupImplementations() internal {
        address metaVaultImplementation = address(new MetaVault());
        vm.expectRevert();
        metaVaultFactory.setMetaVaultImplementation(metaVaultImplementation);
        vm.prank(multisig);
        metaVaultFactory.setMetaVaultImplementation(metaVaultImplementation);
    }
}
