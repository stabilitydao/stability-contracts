// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC4626UniversalTest, IERC4626} from "../base/ERC4626Test.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {WrappedMetaVault} from "../../src/core/vaults/WrappedMetaVault.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {EulerStrategy} from "../../src/strategies/EulerStrategy.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";

contract WrapperERC4626scUSDSonicTest is ERC4626UniversalTest {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVaultFactory public metaVaultFactory;

    function setUp() public override {
        ERC4626UniversalTest.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "sonic";
        overrideBlockNumber = 30141969;

        // Stability scUSD
        wrapper = IERC4626(SonicConstantsLib.WRAPPED_METAVAULT_metascUSD);
        // Donor of USDC.e
        underlyingDonor = 0xe6605932e4a686534D19005BB9dB0FBA1F101272;
        amountToDonate = 1e6 * 1e6;
    }

    function _upgradeThings() internal override {
        multisig = IPlatform(PLATFORM).multisig();
        metaVaultFactory = IMetaVaultFactory(IPlatform(PLATFORM).metaVaultFactory());

        address newMetaVaultImplementation = address(new MetaVault());
        address newWrapperImplementation = address(new WrappedMetaVault());
        vm.startPrank(multisig);
        metaVaultFactory.setMetaVaultImplementation(newMetaVaultImplementation);
        metaVaultFactory.setWrappedMetaVaultImplementation(newWrapperImplementation);
        address[] memory proxies = new address[](2);
        proxies[0] = SonicConstantsLib.METAVAULT_metascUSD;
        proxies[1] = SonicConstantsLib.WRAPPED_METAVAULT_metascUSD;
        metaVaultFactory.upgradeMetaProxies(proxies);
        vm.stopPrank();

        _upgradeCVaults();
        _upgradeStrategy(0x6FFECd5BAC804aAae0BeD79596Af05841819d471); //todo strategy of VAULT_C_scUSD_Euler_Re7Labs
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

        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_scUSD_S_46);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_scUSD_Euler_Re7Labs);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_scUSD_Euler_MevCapital);
        factory.upgradeVaultProxy(SonicConstantsLib.VAULT_C_USDC_Stability_StableJack);
    }

    function _upgradeStrategy(address strategyAddress) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new EulerStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.EULER,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(strategyAddress);
    }
}
