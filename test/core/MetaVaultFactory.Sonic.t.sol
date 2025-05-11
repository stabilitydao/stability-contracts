// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console, Vm} from "forge-std/Test.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IMetaProxy} from "../../src/interfaces/IMetaProxy.sol";
import {Platform} from "../../src/core/Platform.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {MetaVaultFactory, IMetaVaultFactory, IControllable} from "../../src/core/MetaVaultFactory.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";

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
        _upgradeCVaults();

        // console.logBytes32(keccak256(abi.encode(uint256(keccak256("erc7201:stability.MetaVaultFactory")) - 1)) & ~bytes32(uint256(0xff)));
    }

    function test_deployMetaVault() public {
        bytes32 salt = "0x01";

        bytes32 initCodeHash = metaVaultFactory.getMetaVaultProxyInitCodeHash();
        address predictedProxyAddress =
            metaVaultFactory.getCreate2Address(salt, initCodeHash, address(metaVaultFactory));
        address[] memory vaults_ = new address[](3);
        vaults_[0] = SonicConstantsLib.VAULT_C_USDC_SiF;
        vaults_[1] = SonicConstantsLib.VAULT_C_USDC_scUSD_ISF_scUSD;
        vaults_[2] = SonicConstantsLib.VAULT_C_USDC_scUSD_ISF_USDC;
        uint[] memory proportions_ = new uint[](3);
        proportions_[0] = 50e16;
        proportions_[1] = 30e16;
        proportions_[2] = 20e16;
        vm.prank(multisig);
        address metaVault = metaVaultFactory.deployMetaVault(
            salt, VaultTypeLib.METAVAULT, address(0), "testUSD", "Test USD coin", vaults_, proportions_
        );
        assertEq(metaVault, predictedProxyAddress);

        assertEq(metaVaultFactory.metaVaults()[0], metaVault);
        assertEq(metaVaultFactory.metaVaultImplementation(), IMetaProxy(metaVault).implementation());
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

    function _upgradeCVaults() internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        // deploy new impl and upgrade
        address vaultImplementation = address(new CVault());
        vm.prank(multisig);
        factory.setVaultConfig(
            IFactory.VaultConfig({
                vaultType: VaultTypeLib.COMPOUNDING,
                implementation: vaultImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                buildingPrice: 1e10
            })
        );

        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_SiF);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_scUSD_ISF_scUSD);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_scUSD_ISF_USDC);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_8);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_27);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_34);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_36);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_S_49);
    }
}
