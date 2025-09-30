// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {EulerStrategy} from "../../src/strategies/EulerStrategy.sol";
import {SiloFarmStrategy} from "../../src/strategies/SiloFarmStrategy.sol";
import {SiloManagedFarmStrategy} from "../../src/strategies/SiloManagedFarmStrategy.sol";
import {SiloStrategy} from "../../src/strategies/SiloStrategy.sol";
import {AaveStrategy} from "../../src/strategies/AaveStrategy.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";
import {IAToken} from "../../src/integrations/aave/IAToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IPool} from "../../src/integrations/aave/IPool.sol";
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
import {Factory} from "../../src/core/Factory.sol";
import {IProxy} from "../../src/interfaces/IProxy.sol";

contract WrapperUsdMaxDepositUpgradeSonicTest is Test {
    uint public constant FORK_BLOCK = 33508152; // Jun-12-2025 05:49:24 AM +UTC

    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public constant VAULT_WITH_AAVE_STRATEGY = SonicConstantsLib.VAULT_C_USDC_STABILITY_STABLEJACK;
    uint public constant INDEX_VAULT_WITH_AAVE = 6;
    uint public constant INITIAL_AMOUNT = 5000e6; // 5000 USDC
    uint public constant LARGE_SC_AMOUNT = 7000e6;
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

        metaVault = IMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        multiVault = IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);
        wrappedMetaVault = IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);

        _upgradeFactory(); // upgrade to Factory v2.0.0
    }

    /// @notice #326, #334: Check how maxWithdraw works in wrapped/meta-vault/multi-vault/c-vault with AAVE strategy
    function testMetaVaultUpdate326() public {
        IVault cvault = IVault(VAULT_WITH_AAVE_STRATEGY);
        IStrategy strategy = cvault.strategy();

        // ------------------- upgrade strategy
        _upgradeVaults(SonicConstantsLib.METAVAULT_METAUSD, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, false);
        _upgradeVaults(SonicConstantsLib.METAVAULT_METAUSDC, SonicConstantsLib.WRAPPED_METAVAULT_METAUSDC, true);
        _upgradeVaults(SonicConstantsLib.METAVAULT_METASCUSD, SonicConstantsLib.WRAPPED_METAVAULT_METASCUSD, true);

        // ------------------- deposit large amount into scUSD-sub-metavault
        _setProportionsForDeposit(metaVault, 1);
        _setProportionsForDeposit(multiVault, 0);
        assertEq(metaVault.vaultForDeposit(), SonicConstantsLib.METAVAULT_METASCUSD, "d0");
        if (LARGE_SC_AMOUNT != 0) {
            address[] memory assetsM = metaVault.assetsForDeposit();
            IERC20(assetsM[0]).approve(address(metaVault), type(uint).max);
            deal(assetsM[0], address(this), LARGE_SC_AMOUNT);
            uint[] memory amountsM = new uint[](1);
            amountsM[0] = LARGE_SC_AMOUNT;
            metaVault.depositAssets(assetsM, amountsM, 0, address(this));
            vm.roll(block.number + 6);
        }

        // ------------------- setup vault-to-deposit to deposit in USDC-sub-meta-vault
        _setProportionsForDeposit(metaVault, 0);
        _setProportionsForDeposit(multiVault, INDEX_VAULT_WITH_AAVE);
        assertEq(metaVault.vaultForDeposit(), address(multiVault), "a1");
        assertEq(multiVault.vaultForDeposit(), VAULT_WITH_AAVE_STRATEGY, "a2");

        // ------------------- get meta vault tokens
        {
            address[] memory assetsM = metaVault.assetsForDeposit();
            IERC20(assetsM[0]).approve(address(metaVault), type(uint).max);
            deal(assetsM[0], address(this), INITIAL_AMOUNT);
            uint[] memory amountsM = new uint[](1);
            amountsM[0] = INITIAL_AMOUNT;
            metaVault.depositAssets(assetsM, amountsM, 0, address(this));
            vm.roll(block.number + 6);
        }

        // ------------------- deposit all available meta vault tokens into wrapped meta vault
        uint amountMetaVaultTokens = metaVault.balanceOf(address(this));
        address asset = wrappedMetaVault.asset(); // USDC
        IERC20(asset).approve(address(wrappedMetaVault), type(uint).max);
        wrappedMetaVault.deposit(amountMetaVaultTokens, address(this));
        vm.roll(block.number + 6);

        // ------------------- prepare vaults-to-withdraw
        _setProportionsForWithdraw(metaVault, 0, 1);
        _setProportionsForWithdraw(multiVault, INDEX_VAULT_WITH_AAVE, 0);
        assertEq(metaVault.vaultForWithdraw(), address(multiVault), "b1");
        assertEq(multiVault.vaultForWithdraw(), VAULT_WITH_AAVE_STRATEGY, "b2");

        // ------------------- get maxWithdraw when required amount is available
        uint[4] memory maxWithdrawsWMICBefore = _getMaxWithdraw();
        assertApproxEqAbs(maxWithdrawsWMICBefore[0], amountMetaVaultTokens, 2, "User is able to withdraw all amount");

        // ------------------- borrow almost all cash, leave only expected amount in the pool
        uint amountToLeave = 100e6; // leave some USDC in the pool
        {
            IAToken aToken = IAToken(AaveStrategy(address(strategy)).aaveToken());
            uint availableLiquidity = strategy.maxWithdrawAssets(0)[0];
            _borrowAlmostAllCashAave(IPool(aToken.POOL()), availableLiquidity, amountToLeave);
            availableLiquidity = strategy.maxWithdrawAssets(0)[0];
        }

        // ------------------- get maxWithdraw for wrapped/meta-vault/c-vault
        uint[4] memory maxWithdrawsWMICAfter = _getMaxWithdraw();
        assertApproxEqAbs(
            maxWithdrawsWMICAfter[0],
            amountMetaVaultTokens,
            2,
            "User is able to withdraw all meta vault tokens from unwrapped"
        );

        // ------------------- ensure that we are able to withdraw max withdraw amount from each vault
        _tryWithdrawFromCVault(cvault, maxWithdrawsWMICAfter[3], false);
        _tryWithdrawFromMultiVault(maxWithdrawsWMICAfter[2], false);
        _tryWithdrawFromMetaVault(maxWithdrawsWMICAfter[1], false);
        (uint balance, uint withdrawnAmount) = _tryWithdrawFromWrappedVault(maxWithdrawsWMICAfter[0], false);
        assertApproxEqAbs(
            withdrawnAmount / 1e12,
            (INITIAL_AMOUNT + LARGE_SC_AMOUNT),
            (INITIAL_AMOUNT + LARGE_SC_AMOUNT) / 500, // 0.2% tolerance
            "All deposited amount was withdrawn in USDC"
        );
        assertEq(balance, 0, "All wrapped meta vault tokens were withdrawn");

        // ------------------- ensure that we are NOT able to withdraw more than max withdraw amount from each vault
        _tryWithdrawFromCVault(cvault, maxWithdrawsWMICAfter[3] * 101 / 100, true);
        _tryWithdrawFromMultiVault(maxWithdrawsWMICAfter[2] * 101 / 100, true);
        _tryWithdrawFromMetaVault(maxWithdrawsWMICAfter[1] * 101 / 100, true);
        _tryWithdrawFromWrappedVault(maxWithdrawsWMICAfter[0] * 101 / 100, true);

        //        wrappedMetaVault.withdraw(maxWithdrawsWMICAfter[0], address(this), address(this));
        //        uint[4] memory maxWithdrawsWMICFinal = _getMaxWithdraw();
    }

    function _getMaxWithdraw() internal view returns (uint[4] memory wmcMaxWithdraw) {
        wmcMaxWithdraw = [
            wrappedMetaVault.maxWithdraw(address(this)),
            metaVault.maxWithdraw(address(wrappedMetaVault)),
            multiVault.maxWithdraw(address(metaVault)),
            IVault(VAULT_WITH_AAVE_STRATEGY).maxWithdraw(address(multiVault), 0)
        ];
        //        console.log("max W", wmcMaxWithdraw[0]);
        //        console.log("max M", wmcMaxWithdraw[1]);
        //        console.log("max I", wmcMaxWithdraw[2]);
        //        console.log("max C", wmcMaxWithdraw[3]);
    }

    function _tryWithdrawFromCVault(IVault vault, uint vaultShares, bool expectRevert) internal {
        uint snapshotId = vm.snapshotState();

        address[] memory assets = vault.assets();

        if (expectRevert) vm.expectRevert();
        vm.startPrank(address(multiVault));
        vault.withdrawAssets(assets, vaultShares, new uint[](1));

        vm.revertToState(snapshotId);
    }

    function _tryWithdrawFromMetaVault(uint metaVaultTokens, bool expectRevert) internal {
        uint snapshotId = vm.snapshotState();

        address[] memory assets = metaVault.assetsForWithdraw();

        if (expectRevert) vm.expectRevert();
        vm.startPrank(address(wrappedMetaVault));
        metaVault.withdrawAssets(assets, metaVaultTokens, new uint[](1));

        vm.revertToState(snapshotId);
    }

    function _tryWithdrawFromMultiVault(uint multiVaultTokens_, bool expectRevert) internal {
        uint snapshotId = vm.snapshotState();

        address[] memory assets = multiVault.assets();

        if (expectRevert) vm.expectRevert();
        vm.startPrank(address(metaVault));
        multiVault.withdrawAssets(assets, multiVaultTokens_, new uint[](1));

        vm.revertToState(snapshotId);
    }

    function _tryWithdrawFromWrappedVault(
        uint assetsAmount,
        bool expectRevert
    ) internal returns (uint balanceAfterWithdraw, uint withdrawnAmount) {
        uint snapshotId = vm.snapshotState();

        address asset = wrappedMetaVault.asset();

        uint balanceBefore = IERC20(asset).balanceOf(address(this));
        if (expectRevert) vm.expectRevert();
        vm.startPrank(address(this));
        wrappedMetaVault.withdraw(assetsAmount, address(this), address(this));
        withdrawnAmount = IERC20(asset).balanceOf(address(this)) - balanceBefore;

        balanceAfterWithdraw = wrappedMetaVault.balanceOf(address(this));
        vm.revertToState(snapshotId);
    }

    //region ---------------------- Auxiliary functions
    function _upgradeVaults(address metaVault_, address wrapped_, bool upgradeStrategies_) internal {
        multisig = IPlatform(PLATFORM).multisig();
        metaVaultFactory = IMetaVaultFactory(IPlatform(PLATFORM).metaVaultFactory());

        address newMetaVaultImplementation = address(new MetaVault());
        address newWrapperImplementation = address(new WrappedMetaVault());
        vm.startPrank(multisig);

        metaVaultFactory.setMetaVaultImplementation(newMetaVaultImplementation);
        metaVaultFactory.setWrappedMetaVaultImplementation(newWrapperImplementation);

        address[] memory proxies = new address[](2);
        proxies[0] = metaVault_;
        proxies[1] = wrapped_;
        metaVaultFactory.upgradeMetaProxies(proxies);
        vm.stopPrank();

        _upgradeCVaultsWithStrategies(IMetaVault(metaVault_), upgradeStrategies_);
    }

    function _upgradeCVaultsWithStrategies(IMetaVault metaVault_, bool upgradeStrategies_) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        // deploy new impl and upgrade
        address vaultImplementation = address(new CVault());
        vm.prank(multisig);
        factory.setVaultImplementation(VaultTypeLib.COMPOUNDING, vaultImplementation);

        if (upgradeStrategies_) {
            address[] memory vaults = metaVault_.vaults();

            for (uint i; i < vaults.length; i++) {
                factory.upgradeVaultProxy(vaults[i]);
                if (CommonLib.eq(IVault(payable(vaults[i])).strategy().strategyLogicId(), StrategyIdLib.AAVE)) {
                    _upgradeAaveStrategy(address(IVault(payable(vaults[i])).strategy()));
                } else if (CommonLib.eq(IVault(payable(vaults[i])).strategy().strategyLogicId(), StrategyIdLib.SILO)) {
                    _upgradeSiloStrategy(address(IVault(payable(vaults[i])).strategy()));
                } else if (CommonLib.eq(IVault(payable(vaults[i])).strategy().strategyLogicId(), StrategyIdLib.EULER)) {
                    _upgradeEulerStrategy(address(IVault(payable(vaults[i])).strategy()));
                } else if (
                    CommonLib.eq(IVault(payable(vaults[i])).strategy().strategyLogicId(), StrategyIdLib.SILO_FARM)
                ) {
                    _upgradeSiloFarmStrategy(address(IVault(payable(vaults[i])).strategy()));
                } else if (
                    CommonLib.eq(
                        IVault(payable(vaults[i])).strategy().strategyLogicId(), StrategyIdLib.SILO_MANAGED_FARM
                    )
                ) {
                    _upgradeSiloManagedFarmStrategy(address(IVault(payable(vaults[i])).strategy()));
                } else {
                    revert("Unknown strategy for CVault");
                }
            }
        }
    }

    function _upgradeAaveStrategy(address strategyAddress) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new AaveStrategy());
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.AAVE, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
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

    function _upgradeSiloFarmStrategy(address strategyAddress) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new SiloFarmStrategy());
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.SILO_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeSiloManagedFarmStrategy(address strategyAddress) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new SiloManagedFarmStrategy());
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.SILO_MANAGED_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _borrowAlmostAllCashAave(IPool pool, uint cash, uint leftAmount) internal {
        address borrowAsset = SonicConstantsLib.TOKEN_USDC;
        address collateralAsset = SonicConstantsLib.TOKEN_SCUSD;

        uint borrowAmount = cash - leftAmount;
        uint collateralAmount = borrowAmount * 130 / 100;

        deal(collateralAsset, address(this), collateralAmount);
        IERC20(collateralAsset).approve(address(pool), collateralAmount);

        IPool.ReserveData memory reserveData = pool.getReserveData(borrowAsset);
        uint liquidityBefore = IERC20(borrowAsset).balanceOf(reserveData.aTokenAddress);

        pool.supply(collateralAsset, collateralAmount, address(this), 0);
        pool.borrow(borrowAsset, borrowAmount, 2, 0, address(this));

        uint liquidityAfter = IERC20(borrowAsset).balanceOf(reserveData.aTokenAddress);
        assertGt(liquidityBefore, liquidityAfter, "Aave cash was not borrowed");
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

    function _showProportions(IMetaVault metaVault_) internal view {
        uint[] memory props = metaVault_.targetProportions();
        uint[] memory current = metaVault_.currentProportions();
        for (uint i; i < current.length; ++i) {
            console.log("i, current, target", i, current[i], props[i]);
        }
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
