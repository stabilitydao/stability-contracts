// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC4626UniversalTest, IERC4626} from "../base/ERC4626Test.sol";
import {SlippageTestUtils} from "../base/SlippageTestUtils.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {WrappedMetaVault} from "../../src/core/vaults/WrappedMetaVault.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IWrappedMetaVault} from "../../src/interfaces/IWrappedMetaVault.sol";
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
import {Factory} from "../../src/core/Factory.sol";
import {IProxy} from "../../src/interfaces/IProxy.sol";

contract WrapperERC4626scUSDSonicTest is ERC4626UniversalTest, SlippageTestUtils {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVaultFactory public metaVaultFactory;

    function setUp() public override {
        ERC4626UniversalTest.setUp();
    }

    function setUpForkTestVariables() internal override {
        network = "sonic";
        overrideBlockNumber = 30141969;

        // Stability scUSD
        wrapper = IERC4626(SonicConstantsLib.WRAPPED_METAVAULT_METASCUSD);
        // Donor of USDC.e
        underlyingDonor = 0xe6605932e4a686534D19005BB9dB0FBA1F101272;
        amountToDonate = 1e6 * 1e6;

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
        proxies[0] = SonicConstantsLib.METAVAULT_METASCUSD;
        proxies[1] = SonicConstantsLib.WRAPPED_METAVAULT_METASCUSD;
        metaVaultFactory.upgradeMetaProxies(proxies);
        vm.stopPrank();

        _upgradeFactory(); // upgrade to Factory v2.0.0
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
        factory.setVaultImplementation(VaultTypeLib.COMPOUNDING, vaultImplementation);

        address[3] memory vaults = [
            SonicConstantsLib.VAULT_C_SCUSD_S_46,
            SonicConstantsLib.VAULT_C_SCUSD_EULER_RE7LABS,
            SonicConstantsLib.VAULT_C_SCUSD_EULER_MEVCAPITAL
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
        factory.setStrategyImplementation(StrategyIdLib.EULER, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeSiloStrategy(address strategyAddress) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new SiloStrategy());
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.SILO, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _setProportions(uint fromIndex, uint toIndex) internal {
        IMetaVault metaVault = IMetaVault(SonicConstantsLib.METAVAULT_METASCUSD);
        multisig = IPlatform(PLATFORM).multisig();

        uint[] memory props = metaVault.targetProportions();
        props[toIndex] += props[fromIndex] - 2e16;
        props[fromIndex] = 2e16;

        vm.prank(multisig);
        metaVault.setTargetProportions(props);
    }

    function _upgradeFactory() internal {
        // deploy new Factory implementation
        address newImpl = address(new Factory());

        // get the proxy address for the factory
        address factoryProxy = address(IPlatform(PLATFORM).factory());

        // prank as the platform because only it can upgrade
        vm.prank(PLATFORM);
        IProxy(factoryProxy).upgrade(newImpl);
    }
    //endregion ---------------------- Auxiliary functions
}
