// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../src/strategies/AaveStrategy.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";
import {EulerStrategy} from "../../src/strategies/EulerStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IEVC, IEthereumVaultConnector} from "../../src/integrations/euler/IEthereumVaultConnector.sol";
import {IEulerVault} from "../../src/integrations/euler/IEulerVault.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IWrappedMetaVault} from "../../src/interfaces/IWrappedMetaVault.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {WrappedMetaVault} from "../../src/core/vaults/WrappedMetaVault.sol";
import {console, Test} from "forge-std/Test.sol";


contract WrapperUsdMaxDepositUpgradeSonicTest is Test {
    uint public constant FORK_BLOCK = 33508152; // Jun-12-2025 05:49:24 AM +UTC

    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public constant VAULT_WITH_AAVE_STRATEGY = SonicConstantsLib.VAULT_C_USDC_Stability_StableJack;
    IMetaVaultFactory public metaVaultFactory;
    IPriceReader public priceReader;
    address public multisig;
    IMetaVault public metaVault;
    IMetaVault public multiVault;
    IWrappedMetaVault public wrappedMetaVault;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        multisig = IPlatform(PLATFORM).multisig();
        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
        metaVaultFactory = IMetaVaultFactory(SonicConstantsLib.METAVAULT_FACTORY);

        metaVault = IMetaVault(SonicConstantsLib.METAVAULT_metaUSD);
        multiVault = IMetaVault(SonicConstantsLib.METAVAULT_metaUSDC);
        wrappedMetaVault = IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD);
    }

    /// @notice #326: Check how maxWithdraw works in wrapped/meta-vault/multi-vault/c-vault with AAVE strategy
    function testMetaVaultUpdate326() public {
        IVault cvault = IVault(VAULT_WITH_AAVE_STRATEGY);
        IStrategy strategy = cvault.strategy();

        // ------------------- upgrade strategy
        _upgradeVaults();
        _upgradeAaveStrategy(address(strategy));

        // ------------------- setup vault-to-withdraw and make deposit
        uint amount = 0;
        uint amountToInc = 5000e6;
        while (
            metaVault.vaultForWithdraw() != SonicConstantsLib.METAVAULT_metaUSDC
            || IMetaVault(metaVault.vaultForWithdraw()).vaultForWithdraw() != VAULT_WITH_AAVE_STRATEGY
        ) {
            // todo
            address[] memory assets = IMetaVault(metaVault.vaultForWithdraw()).assets();
            deal(assets[0], address(this), amountToInc);
            IERC20(assets[0]).approve(address(wrappedMetaVault), type(uint).max);
            wrappedMetaVault.deposit(amountToInc, address(this));
            amount += amountToInc;
        }
        assertEq(IMetaVault(metaVault.vaultForWithdraw()).vaultForWithdraw(), VAULT_WITH_AAVE_STRATEGY, "we need a vault with the given AAVE strategy");

        // ------------------- get maxWithdraw when required amount is available
        uint[4] memory maxWithdrawsWMICBefore = _getMaxWithdraw();
        assertApproxEqAbs(maxWithdrawsWMICBefore[0], amount, 2, "User is able to withdraw all amount");

        // ------------------- borrow almost all cash, leave only expected amount in the pool
        uint amountToLeave = 1000e6; // leave 1000 scUSD in the pool
        {
            IEulerVault eulerVault = IEulerVault(EulerStrategy(address(strategy)).underlying());
            uint cash = eulerVault.cash();
            _borrowAlmostAllCash(eulerVault, cash, amountToLeave);
        }

        // ------------------- get maxWithdraw for wrapped/meta-vault/c-vault
        uint[4] memory maxWithdrawsWMCAfter = _getMaxWithdraw();
        assertApproxEqAbs(maxWithdrawsWMCAfter[0], amountToLeave, 2, "User is able to withdraw only left amount");

        // ------------------- ensure that we are able to withdraw max withdraw amount from each vault
        _tryWithdrawFromCVault(cvault, maxWithdrawsWMCAfter[2], false);
        _tryWithdrawFromMetaVault(maxWithdrawsWMCAfter[1], false);
        _tryWithdrawFromWrappedVault(maxWithdrawsWMCAfter[0], false);

        // ------------------- ensure that we are NOT able to withdraw more than max withdraw amount from each vault
        _tryWithdrawFromCVault(cvault, maxWithdrawsWMCAfter[2] * 101/100, true);
        _tryWithdrawFromMetaVault(maxWithdrawsWMCAfter[1] * 101/100, true);
        _tryWithdrawFromWrappedVault(maxWithdrawsWMCAfter[0] * 101/100, true);
    }

    function _getMaxWithdraw() internal view returns (uint[4] memory wmcMaxWithdraw) {
        wmcMaxWithdraw = [
            wrappedMetaVault.maxWithdraw(address(this)),
            metaVault.maxWithdraw(address(wrappedMetaVault)),
            multiVault.maxWithdraw(address(metaVault)),
            IVault(VAULT_WITH_AAVE_STRATEGY).maxWithdraw(address(multiVault))
        ];
        console.log("max W", wmcMaxWithdraw[0]);
        console.log("max M", wmcMaxWithdraw[1]);
        console.log("max I", wmcMaxWithdraw[2]);
        console.log("max C", wmcMaxWithdraw[3]);
    }

    function _tryWithdrawFromCVault(IVault vault, uint vaultShares, bool expectRevert) internal {
        uint snapshotId = vm.snapshotState();

        address[] memory assets = vault.assets();

        if (expectRevert) vm.expectRevert();
        vm.startPrank(address(metaVault));
        vault.withdrawAssets(assets, vaultShares, new uint[](1));

        vm.revertToState(snapshotId);
    }

    function _tryWithdrawFromMetaVault(uint metaVaultTokens, bool expectRevert) internal {
        uint snapshotId = vm.snapshotState();

        address[] memory assets = metaVault.assets();

        if (expectRevert) vm.expectRevert();
        vm.startPrank(address(wrappedMetaVault));
        metaVault.withdrawAssets(assets, metaVaultTokens, new uint[](1));

        vm.revertToState(snapshotId);
    }

    function _tryWithdrawFromWrappedVault(uint assetsAmount, bool expectRevert) internal {
        uint snapshotId = vm.snapshotState();

        if (expectRevert) vm.expectRevert();
        vm.startPrank(address(this));
        wrappedMetaVault.withdraw(assetsAmount, address(this), address(this));

        vm.revertToState(snapshotId);
    }

    //region ---------------------- Auxiliary functions
    function _upgradeVaults() internal {
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
            if (CommonLib.eq(IVault(payable(vaults[i])).strategy().strategyLogicId(), StrategyIdLib.AAVE)) {
                _upgradeAaveStrategy(address(IVault(payable(vaults[i])).strategy()));
            }
        }
    }

    function _upgradeAaveStrategy(address strategyAddress) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new AaveStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.AAVE,
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

    function _borrowAlmostAllCash(IEulerVault eulerVault, uint cash, uint leftAmount) internal {
        IEulerVault collateralVault = IEulerVault(SonicConstantsLib.EULER_VAULT_wS_Re7);
        IEthereumVaultConnector evc = IEthereumVaultConnector(payable(collateralVault.EVC()));

        uint collateralAmount = cash * 10 * 10**12; // borrow scUSD, collateral is wS

        deal(SonicConstantsLib.TOKEN_wS, address(this), collateralAmount);
        IERC20(SonicConstantsLib.TOKEN_wS).approve(address(collateralVault), collateralAmount);

        uint256 borrowAmount = cash - leftAmount;

        // console.log("Enabling borrow controller...");
        evc.enableController(address(this), address(eulerVault));

        // console.log("Enabling collateral...");
        evc.enableCollateral(address(this), address(collateralVault));

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](2);

        bytes memory depositData = abi.encodeWithSelector(
            IEulerVault.deposit.selector,
            collateralAmount,
            address(this)
        );
        items[0] = IEVC.BatchItem({
            targetContract: address(collateralVault),
            onBehalfOfAccount: address(this),
            value: 0,
            data: depositData
        });

        bytes memory borrowData = abi.encodeWithSelector(
            IEulerVault.borrow.selector,
            borrowAmount,
            address(this)
        );
        items[1] = IEVC.BatchItem({
            targetContract: address(eulerVault),
            onBehalfOfAccount: address(this),
            value: 0,
            data: borrowData
        });

        uint cashBefore = eulerVault.cash();
        evc.batch(items);
        assertGt(cashBefore, eulerVault.cash(), "Euler cash was not borrowed");
    }

    function _setProportions(uint fromIndex, uint toIndex) internal {
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
    //endregion ---------------------- Auxiliary functions
}
