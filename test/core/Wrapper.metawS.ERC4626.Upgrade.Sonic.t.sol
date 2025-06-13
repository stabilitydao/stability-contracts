// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CVault} from "../../src/core/vaults/CVault.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";
import {ERC4626UniversalTest, IERC4626} from "../base/ERC4626Test.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IWrappedMetaVault} from "../../src/interfaces/IWrappedMetaVault.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {SiloFarmStrategy} from "../../src/strategies/SiloFarmStrategy.sol";
import {SiloManagedFarmStrategy} from "../../src/strategies/SiloManagedFarmStrategy.sol";
import {SlippageTestUtils} from "../base/SlippageTestUtils.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {Test, console} from "forge-std/Test.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {WrappedMetaVault} from "../../src/core/vaults/WrappedMetaVault.sol";

contract WrapperERC4626wSSonicTest is ERC4626UniversalTest, SlippageTestUtils {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVaultFactory public metaVaultFactory;

    function setUp() public override {
        ERC4626UniversalTest.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "sonic";
        overrideBlockNumber = 33593160; // Jun-12-2025 02:30:29 PM +UTC

        // Stability wS
        wrapper = IERC4626(SonicConstantsLib.WRAPPED_METAVAULT_metawS);
        // Donor of wS
        underlyingDonor = 0x6C5E14A212c1C3e4Baf6f871ac9B1a969918c131;
        amountToDonate = 1e6 * 1e18;

        minDeposit = 100;
    }

    //region ---------------------- Tests for deposit/withdrawWithSlippage
    function testDepositWithSlippage__Fork__Fuzz(uint amountToDeposit) public {
        // see ERC4626UniversalTest.testDeposit__Fork__Fuzz
        amountToDeposit = bound(amountToDeposit, minDeposit, userInitialUnderlying);

        _testDepositWithSlippage(user, IWrappedMetaVault(address(wrapper)), amountToDeposit, underlyingToken, TOLERANCE);
    }

    function testMintWithSlippage__Fork__Fuzz(uint amountToMint) public {
        // see ERC4626UniversalTest.testMint__Fork__Fuzz
        amountToMint = bound(
            amountToMint,
            minDeposit * underlyingToWrappedFactor,
            userInitialShares - (TOLERANCE * underlyingToWrappedFactor)
        );

        _testMintWithSlippage(user, IWrappedMetaVault(address(wrapper)), amountToMint, underlyingToken, TOLERANCE);
    }

    function testWithdrawWithSlippage__Fork__Fuzz(uint amountToWithdraw) public {
        // see ERC4626UniversalTest._testWithdraw
        amountToWithdraw = bound(amountToWithdraw, minDeposit, userInitialUnderlying - TOLERANCE);

        _testWithdrawWithSlippage(
            user, IWrappedMetaVault(address(wrapper)), amountToWithdraw, underlyingToken, TOLERANCE
        );
    }

    function testRedeemWithSlippage__Fork__Fuzz(uint amountToRedeem) public {
        // see ERC4626UniversalTest.testRedeem__Fork__Fuzz
        amountToRedeem = bound(amountToRedeem, minDeposit * underlyingToWrappedFactor, userInitialShares - TOLERANCE);

        _testRedeemWithSlippage(user, IWrappedMetaVault(address(wrapper)), amountToRedeem, underlyingToken, TOLERANCE);
    }

    //endregion ---------------------- Tests for deposit/withdrawWithSlippage

    function testWithdrawProblemMaxUint() public {
        _testWithdraw(type(uint).max);
    }

    function testWithdrawProblem2175445564() public {
        _testWithdraw(2175445564);
    }

    //region ---------------------- Auxiliary functions
    function _upgradeThings() internal override {
        multisig = IPlatform(PLATFORM).multisig();
        metaVaultFactory = IMetaVaultFactory(IPlatform(PLATFORM).metaVaultFactory());

        address newMetaVaultImplementation = address(new MetaVault());
        address newWrapperImplementation = address(new WrappedMetaVault());
        vm.startPrank(multisig);
        metaVaultFactory.setMetaVaultImplementation(newMetaVaultImplementation);
        metaVaultFactory.setWrappedMetaVaultImplementation(newWrapperImplementation);
        address[] memory proxies = new address[](2);
        proxies[0] = SonicConstantsLib.METAVAULT_metawS;
        proxies[1] = SonicConstantsLib.WRAPPED_METAVAULT_metawS;
        metaVaultFactory.upgradeMetaProxies(proxies);
        address[] memory vaults = IMetaVault(SonicConstantsLib.METAVAULT_metawS).vaults();
        for (uint i; i < vaults.length; ++i) {
            IVault(vaults[i]).setDoHardWorkOnDeposit(false);
        }
        vm.stopPrank();

        _upgradeCVaults();

        // to withdraw from requested subvault, i.e. 4
        // increase it's proportions here, i.e. call _setProportions(1, 4);
        // _setProportions(1, 4);

        // ... and decrease it back in _doBeforeTest()
        // i.e. call _setProportions(4, 1);

        // as result, withdraw will be from 4th subvault
    }

    function _doBeforeTest(uint /* tag */ ) internal override {
        // _setProportions(4, 1);
    }

    function _setProportions(uint fromIndex, uint toIndex) internal {
        IMetaVault metaVault = IMetaVault(SonicConstantsLib.METAVAULT_metaUSDC);
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

        address[2] memory vaults = [
                        SonicConstantsLib.VAULT_C_wS_SiMF_Valmore,
                        SonicConstantsLib.VAULT_C_USDC_SiF_54
            ];

        for (uint i; i < vaults.length; i++) {
            factory.upgradeVaultProxy(vaults[i]);
            if (CommonLib.eq(IVault(payable(vaults[i])).strategy().strategyLogicId(), StrategyIdLib.SILO_MANAGED_FARM)) {
                _upgradeSiloManagedFarmStrategy(address(IVault(payable(vaults[i])).strategy()));
            } else if (CommonLib.eq(IVault(payable(vaults[i])).strategy().strategyLogicId(), StrategyIdLib.SILO_FARM)) {
                _upgradeSiloFarmStrategy(address(IVault(payable(vaults[i])).strategy()));
            }
        }
    }

    function _upgradeSiloManagedFarmStrategy(address strategyAddress) internal {
        console.log("_upgradeSiloManagedFarmStrategy", strategyAddress);
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new SiloManagedFarmStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.SILO_MANAGED_FARM,
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

    function _upgradeSiloFarmStrategy(address strategyAddress) internal {
        console.log("_upgradeSiloFarmStrategy", strategyAddress);
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new SiloFarmStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.SILO_FARM,
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
    //endregion ---------------------- Auxiliary functions
}
