// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SiloStrategy} from "../../src/strategies/SiloStrategy.sol";
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
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IWrappedMetaVault} from "../../src/interfaces/IWrappedMetaVault.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {WrappedMetaVault} from "../../src/core/vaults/WrappedMetaVault.sol";
import {Test} from "forge-std/Test.sol";

contract WrapperScUsdMaxDepositUpgradeSonicTest is Test {
    uint public constant FORK_BLOCK = 34657318; // Jun-12-2025 05:49:24 AM +UTC

    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public constant VAULT_WITH_EULER_STRATEGY = SonicConstantsLib.VAULT_C_SCUSD_EULER_RE7LABS;
    IMetaVaultFactory public metaVaultFactory;
    IPriceReader public priceReader;
    address public multisig;
    IMetaVault public metaVault;
    IWrappedMetaVault public wrappedMetaVault;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        multisig = IPlatform(PLATFORM).multisig();
        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
        metaVaultFactory = IMetaVaultFactory(SonicConstantsLib.METAVAULT_FACTORY);

        metaVault = IMetaVault(SonicConstantsLib.METAVAULT_METASCUSD);
        wrappedMetaVault = IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METASCUSD);
    }

    /// @notice #326, #334: Check how maxWithdraw works in wrapped/meta-vault/c-vault with Euler strategy
    function testMetaVaultUpdate326() public {
        IVault cvault = IVault(VAULT_WITH_EULER_STRATEGY);
        IStrategy strategy = cvault.strategy();
        address[] memory assets = cvault.assets();

        // ------------------- upgrade strategy
        _upgradeVaults();
        _upgradeEulerStrategy(address(strategy));

        // ------------------- setup vault-to-withdraw and make deposit
        uint amount = 0;
        uint amountToInc = 5000e6;
        while (metaVault.vaultForWithdraw() != VAULT_WITH_EULER_STRATEGY) {
            address asset = wrappedMetaVault.asset(); // scUSD, decimals 6
            deal(asset, address(this), amountToInc);
            IERC20(assets[0]).approve(address(wrappedMetaVault), type(uint).max);
            wrappedMetaVault.deposit(amountToInc, address(this));
            amount += amountToInc;
        }
        assertEq(
            metaVault.vaultForWithdraw(), VAULT_WITH_EULER_STRATEGY, "we need a vault with the given Euler strategy"
        );

        // ------------------- get maxWithdraw when required amount is available
        uint[3] memory maxWithdrawsWMCBefore = _getMaxWithdrawWMC();
        assertApproxEqAbs(maxWithdrawsWMCBefore[0], amount, 2, "User is able to withdraw all amount");

        // ------------------- borrow almost all cash, leave only expected amount in the pool
        uint amountToLeave = 1000e6; // leave 1000 scUSD in the pool
        _reduceCashInEulerStrategy(amountToLeave, address(strategy));

        // ------------------- get maxWithdraw for wrapped/meta-vault/c-vault
        uint[3] memory maxWithdrawsWMCAfter = _getMaxWithdrawWMC();
        assertLt(
            maxWithdrawsWMCAfter[2],
            maxWithdrawsWMCBefore[2],
            "User is able to withdraw less than all amount from CVault"
        );

        // ------------------- ensure that we are able to withdraw max withdraw amount from each vault
        _tryWithdrawFromCVault(cvault, maxWithdrawsWMCAfter[2], false);
        _tryWithdrawFromMetaVault(maxWithdrawsWMCAfter[1], false);
        _tryWithdrawFromWrappedVault(maxWithdrawsWMCAfter[0], false);

        // ------------------- ensure that we are NOT able to withdraw more than max withdraw amount from each vault
        _tryWithdrawFromCVault(cvault, maxWithdrawsWMCAfter[2] * 101 / 100, true);
        _tryWithdrawFromMetaVault(maxWithdrawsWMCAfter[1] * 101 / 100, true);
        _tryWithdrawFromWrappedVault(maxWithdrawsWMCAfter[0] * 101 / 100, true);
    }

    /// @notice #326, #334: Check how maxWithdraw works in meta-vault/c-vault with Euler strategy
    /// User balance exceeds sub-vault balance in meta-vault-tokens
    function testUserBalanceExceedsSubVaultBalance326() public {
        IVault cvault = IVault(VAULT_WITH_EULER_STRATEGY);
        IStrategy strategy = cvault.strategy();

        // ------------------- upgrade strategy
        _upgradeVaults();

        // ------------------- setup vault-to-withdraw and make deposit
        address[] memory assets = metaVault.assets();
        uint amount = 0;
        uint amountToInc = 500_000e6;
        for (uint i; i < 2; ++i) {
            do {
                deal(assets[0], address(this), amountToInc);
                IERC20(assets[0]).approve(address(metaVault), type(uint).max);
                uint[] memory amounts = new uint[](1);
                amounts[0] = amountToInc;
                metaVault.depositAssets(assets, amounts, 0, address(this));
                amount += amountToInc;
            } while (metaVault.vaultForWithdraw() != VAULT_WITH_EULER_STRATEGY);
        }
        assertEq(
            metaVault.vaultForWithdraw(), VAULT_WITH_EULER_STRATEGY, "we need a vault with the given Euler strategy"
        );

        // ------------------- check maxWithdraw
        uint[3] memory amountsBefore = _getMaxWithdrawTwoBalances();
        assertGt(
            amountsBefore[0], amountsBefore[2], "total user metavault balance > subvault balance in metavault-tokens"
        );
        assertApproxEqAbs(
            amountsBefore[0], amountsBefore[1], 2, "user is able to withdraw all amount (from multiple subvaults)"
        );

        uint amountToLeave = 1000e6; // leave 1000 scUSD in the pool
        _reduceCashInEulerStrategy(amountToLeave, address(strategy));

        uint[3] memory amountsAfter = _getMaxWithdrawTwoBalances();
        assertGt(amountsBefore[0], amountsAfter[0], "max withdraw is reduced");
        assertGt(amountsAfter[0], amountsAfter[2], "max withdraw > sub-vault balance in meta-vault-tokens");

        uint[] memory minAmounts = new uint[](1);
        minAmounts[0] = amountsAfter[0] * 99 / 100 / 1e12; // 1% slippage

        _tryWithdrawFromMetaVault(amountsAfter[0], false, minAmounts, address(this));
        _tryWithdrawFromMetaVault(amountsAfter[0] + 1, true, minAmounts, address(this));
    }

    //region ---------------------- Internal logic
    function _getMaxWithdrawWMC() internal view returns (uint[3] memory wmcMaxWithdraw) {
        wmcMaxWithdraw = [
            wrappedMetaVault.maxWithdraw(address(this)),
            metaVault.maxWithdraw(address(wrappedMetaVault)),
            IVault(VAULT_WITH_EULER_STRATEGY).maxWithdraw(address(metaVault), 0)
        ];
        //        console.log("max W", wmcMaxWithdraw[0]);
        //        console.log("max M", wmcMaxWithdraw[1]);
        //        console.log("max C", wmcMaxWithdraw[2]);
    }

    function _getMaxWithdrawTwoBalances() internal view returns (uint[3] memory amounts) {
        uint balanceSubVault = IStabilityVault(metaVault.vaultForWithdraw()).balanceOf(address(metaVault));
        (uint sharePriceSubVault,) = IStabilityVault(metaVault.vaultForWithdraw()).price();
        (uint priceAsset,) = metaVault.price();

        amounts = [
            metaVault.maxWithdraw(address(this)),
            metaVault.balanceOf(address(this)),
            balanceSubVault * sharePriceSubVault / priceAsset
        ];
        //        console.log("amounts[0] (max withdraw):", amounts[0]);
        //        console.log("amounts[1] (user balance in meta-vault):", amounts[1]);
        //        console.log("amounts[2] (sub-vault balance in meta-vault-tokens):", amounts[2]);
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

    function _tryWithdrawFromMetaVault(
        uint metaVaultTokens,
        bool expectRevert,
        uint[] memory minAmounts,
        address user
    ) internal {
        uint snapshotId = vm.snapshotState();

        address[] memory assets = metaVault.assets();

        if (expectRevert) vm.expectRevert();
        vm.startPrank(user);
        metaVault.withdrawAssets(assets, metaVaultTokens, minAmounts);

        vm.revertToState(snapshotId);
    }

    function _tryWithdrawFromWrappedVault(uint assetsAmount, bool expectRevert) internal {
        uint snapshotId = vm.snapshotState();

        if (expectRevert) vm.expectRevert();
        vm.startPrank(address(this));
        wrappedMetaVault.withdraw(assetsAmount, address(this), address(this));

        vm.revertToState(snapshotId);
    }

    function _reduceCashInEulerStrategy(uint amountToLeave, address strategy) internal returns (uint cashBefore) {
        IEulerVault eulerVault = IEulerVault(EulerStrategy(strategy).underlying());
        cashBefore = eulerVault.cash();
        _borrowAlmostAllCash(eulerVault, cashBefore, amountToLeave);
    }
    //endregion ---------------------- Internal logic

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
        proxies[0] = SonicConstantsLib.METAVAULT_METASCUSD;
        proxies[1] = SonicConstantsLib.WRAPPED_METAVAULT_METASCUSD;
        metaVaultFactory.upgradeMetaProxies(proxies);
        vm.stopPrank();

        _upgradeCVaultsWithStrategies();
    }

    function _upgradeCVaultsWithStrategies() internal {
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
            if (CommonLib.eq(IVault(payable(vaults[i])).strategy().strategyLogicId(), StrategyIdLib.SILO)) {
                _upgradeSiloStrategy(address(IVault(payable(vaults[i])).strategy()));
            } else if (CommonLib.eq(IVault(payable(vaults[i])).strategy().strategyLogicId(), StrategyIdLib.EULER)) {
                _upgradeEulerStrategy(address(IVault(payable(vaults[i])).strategy()));
            } else {
                revert("Unknown strategy for CVault");
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

    function _borrowAlmostAllCash(IEulerVault eulerVault, uint cash, uint leftAmount) internal {
        IEulerVault collateralVault = IEulerVault(SonicConstantsLib.EULER_VAULT_WS_RE7);
        IEthereumVaultConnector evc = IEthereumVaultConnector(payable(collateralVault.EVC()));

        uint collateralAmount = cash * 10 * 10 ** 12; // borrow scUSD, collateral is wS

        deal(SonicConstantsLib.TOKEN_WS, address(this), collateralAmount);
        IERC20(SonicConstantsLib.TOKEN_WS).approve(address(collateralVault), collateralAmount);

        uint borrowAmount = cash - leftAmount;

        // console.log("Enabling borrow controller...");
        evc.enableController(address(this), address(eulerVault));

        // console.log("Enabling collateral...");
        evc.enableCollateral(address(this), address(collateralVault));

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](2);

        bytes memory depositData = abi.encodeWithSelector(IEulerVault.deposit.selector, collateralAmount, address(this));
        items[0] = IEVC.BatchItem({
            targetContract: address(collateralVault),
            onBehalfOfAccount: address(this),
            value: 0,
            data: depositData
        });

        bytes memory borrowData = abi.encodeWithSelector(IEulerVault.borrow.selector, borrowAmount, address(this));
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

    function _setProportionsForDeposit(IMetaVault metaVault_, uint targetIndex) internal {
        multisig = IPlatform(PLATFORM).multisig();
        // _showProportions(metaVault_);
        // console.log(metaVault_.vaultForDeposit(), metaVault_.vaultForWithdraw());

        uint[] memory props = metaVault_.targetProportions();
        uint len = props.length;
        for (uint i = 0; i < len; ++i) {
            if (i == targetIndex) {
                props[targetIndex] = 1e18 - 1e16 * (len - 1);
            } else {
                props[i] = 1e16;
            }
        }

        vm.prank(multisig);
        metaVault_.setTargetProportions(props);

        // _showProportions(metaVault_);
        // console.log(metaVault_.vaultForDeposit(), metaVault_.vaultForWithdraw());
    }

    function _setProportionsForWithdraw(IMetaVault metaVault_, uint targetIndex, uint fromIndex) internal {
        multisig = IPlatform(PLATFORM).multisig();
        // _showProportions(metaVault_);
        // console.log(metaVault_.vaultForDeposit(), metaVault_.vaultForWithdraw());

        uint total = 0;
        uint[] memory props = metaVault_.currentProportions();
        for (uint i = 0; i < props.length; ++i) {
            if (i != targetIndex && i != fromIndex) {
                total += props[i];
            }
        }

        props[fromIndex] = 1e18 - total - 1e16;
        props[targetIndex] = 1e16;

        vm.prank(multisig);
        metaVault_.setTargetProportions(props);

        // _showProportions(metaVault_);
        // console.log(metaVault_.vaultForDeposit(), metaVault_.vaultForWithdraw());
    }
    //endregion ---------------------- Auxiliary functions
}
