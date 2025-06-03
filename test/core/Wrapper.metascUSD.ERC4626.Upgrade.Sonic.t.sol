// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// import {Test, console} from "forge-std/Test.sol";
import {ERC4626UniversalTest, IERC4626} from "../base/ERC4626Test.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {WrappedMetaVault} from "../../src/core/vaults/WrappedMetaVault.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {EulerStrategy} from "../../src/strategies/EulerStrategy.sol";
import {SiloStrategy} from "../../src/strategies/SiloStrategy.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";

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

        minDeposit = 110; // avoid UsdAmountLessThreshold
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

        // to withdraw from requested subvault, i.e. 2
        // increase it's proportions here, i.e. call _setProportions(1, 2);
        _setProportions(2, 0);

        // ... and decrease it back in _doBeforeTest()
        // i.e. call _setProportions(2, 1);

        // as result, withdraw will be from 2th subvault
    }

    function _doBeforeTest(uint /* tag */ ) internal override {
        _setProportions(0, 2);
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

        address[3] memory vaults = [
            SonicConstantsLib.VAULT_C_scUSD_S_46,
            SonicConstantsLib.VAULT_C_scUSD_Euler_Re7Labs,
            SonicConstantsLib.VAULT_C_scUSD_Euler_MevCapital
        ];

        for (uint i; i < vaults.length; i++) {
            factory.upgradeVaultProxy(vaults[i]);
            if (CommonLib.eq(IVault(payable(vaults[i])).strategy().strategyLogicId(), StrategyIdLib.EULER)) {
                _upgradeEulerStrategy(address(IVault(payable(vaults[i])).strategy()));
            } else if (CommonLib.eq(IVault(payable(vaults[i])).strategy().strategyLogicId(), StrategyIdLib.SILO)) {
                _upgradeSiloStrategy(address(IVault(payable(vaults[i])).strategy()));
            }
        }
    }

    function _upgradeEulerStrategy(address strategyAddress) internal {
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

    function _upgradeSiloStrategy(address strategyAddress) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new SiloStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.SILO,
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

    function _setProportions(uint fromIndex, uint toIndex) internal {
        IMetaVault metaVault = IMetaVault(SonicConstantsLib.METAVAULT_metascUSD);
        multisig = IPlatform(PLATFORM).multisig();

        uint[] memory props = metaVault.targetProportions();
        props[toIndex] += props[fromIndex] - 2e16;
        props[fromIndex] = 2e16;

        vm.prank(multisig);
        metaVault.setTargetProportions(props);

        //        props = metaVault.targetProportions();
        //        uint[] memory current = metaVault.currentProportions();
        //        for (uint i; i < current.length; ++i) {
        //            console.log("i, current, target", i, current[i], props[i]);
        //        }
    }
}
