// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IchiSwapXFarmStrategy} from "../../src/strategies/IchiSwapXFarmStrategy.sol";
import {SiloAdvancedLeverageStrategy} from "../../src/strategies/SiloAdvancedLeverageStrategy.sol";
import {SiloManagedFarmStrategy} from "../../src/strategies/SiloManagedFarmStrategy.sol";
import {SiloStrategy} from "../../src/strategies/SiloStrategy.sol";
import {SiloFarmStrategy} from "../../src/strategies/SiloFarmStrategy.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {console, Test} from "forge-std/Test.sol";
import {IStrategyProxy} from "../../src/interfaces/IStrategyProxy.sol";

/// @notice Test multiple vaults on given/current block and save summary report to the file
contract CVaultUpgradeBatchSonicTest is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;

    /// @dev This block is used if there is no SONIC_VAULT_BATCH_BLOCK env var set
    uint public constant FORK_BLOCK = 43911991; // Aug-21-2025 04:58:57 AM +UTC
    IFactory public factory;
    address public multisig;

    address[3] internal VAULT_UNDER_TEST;

    struct TestResult {
        bool success;
        /// @dev Summary of gas consumed during deposit, withdraw and (probably) any other vault actions in the test
        uint totalGasConsumed;
        /// @dev Total losses of the user in percents after all vault operations, 100% = 1e18; 0 for negative losses
        uint lossPercent;
        /// @dev Total earnings of the user in percents after all vault operations, 100% = 1e18; 0 for negative earnings
        uint earningsPercent;
    }

    constructor() {
        // ---------------- use current block by default or given block from env var
        uint _block = vm.envOr("SONIC_VAULT_BATCH_BLOCK", uint(FORK_BLOCK));
        if (_block == 0) {
            vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        } else {
            vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), _block));
        }

        factory = IFactory(IPlatform(PLATFORM).factory());
        multisig = IPlatform(PLATFORM).multisig();

        // ---------------- create list of vaults to test
        VAULT_UNDER_TEST = [
            SonicConstantsLib.VAULT_LEV_SiAL_wstkscUSD_USDC,
            SonicConstantsLib.VAULT_LEV_SiAL_wstkscETH_WETH,
            SonicConstantsLib.VAULT_LEV_SiAL_aSonUSDC_scUSD_14AUG2025
        ];
    }

    function testDepositWithdrawBatch() internal {
        TestResult[] memory results = new TestResult[](VAULT_UNDER_TEST.length);
        bool success = true;

        console.log(">>>>> Start Batch Sonic CVault upgrade test >>>>>");
        for (uint i = 0; i < VAULT_UNDER_TEST.length; i++) {
            uint snapshot = vm.snapshotState();
            results[i] = _testDepositWithdrawSingleVault(VAULT_UNDER_TEST[i], true, 0);
            vm.revertToState(snapshot);

            success = success && results[i].success;
        }
        console.log("<<<< Finish Batch Sonic CVault upgrade test <<<<");

        _saveResults(results);

        assertEq(success, true, "All vaults should pass deposit/withdraw test");
    }

    function testDepositWithdrawSingle() public {
        TestResult memory r = _testDepositWithdrawSingleVault(VAULT_UNDER_TEST[1], false, 1e16);
        assertEq(r.success, true, "Selected vault should pass deposit/withdraw test");
    }

    //region ---------------------- Auxiliary functions
    function _testDepositWithdrawSingleVault(address vault_, bool catchError, uint amount_) internal returns (TestResult memory result) {
        IStabilityVault vault = IStabilityVault(vault_);

        _upgradeCVault(vault_);
        _upgradeVaultStrategy(vault_);

        result = _testDepositWithdraw(vault, catchError, amount_);

        if (result.success) {
            console.log("Success: vault, gas, earning/loss %",
                vault.symbol(),
                result.totalGasConsumed,
                result.earningsPercent > 0
                    ? result.earningsPercent * 100_000 / 1e18
                    : result.lossPercent * 100_000 / 1e18
            );
        } else {
            console.log(
                "Failed:",
                vault.symbol(),
                address(vault)
            );
        }

        return result;
    }

    function _testDepositWithdraw(IStabilityVault vault, bool catchError, uint amount_) internal returns (TestResult memory result) {
        // --------------- prepare amount to deposit
        (address[] memory assets, uint[] memory depositAmounts) = _dealAndApprove(vault, address(this), amount_);
        uint balanceBefore = IERC20(assets[0]).balanceOf(address(this));

        // --------------- deposit
        uint gas0 = gasleft();
        if (catchError) {
            try vault.depositAssets(assets, depositAmounts, 0, address(this)) {
                result.success = true;
            } catch {
                result.success = false;
            }
        } else {
            vault.depositAssets(assets, depositAmounts, 0, address(this));
            result.success = true;
        }
        result.totalGasConsumed = gas0 - gasleft();

        vm.roll(block.number + 6);

        // --------------- withdraw
        if (result.success) {
            uint maxWithdraw = vault.maxWithdraw(address(this));

            gas0 = gasleft();
            if (catchError) {
                try vault.withdrawAssets(assets, maxWithdraw, new uint[](1)) {
                    result.success = true;
                } catch {
                    result.success = false;
                }
            } else {
                vault.withdrawAssets(assets, maxWithdraw, new uint[](1));
                result.success = true;
            }
            result.totalGasConsumed = gas0 - gasleft();
        }

        // --------------- check results
        uint balanceAfter = IERC20(assets[0]).balanceOf(address(this));
        if (balanceAfter > balanceBefore) {
            result.earningsPercent = (balanceAfter - balanceBefore) * 1e18 / balanceBefore;
            result.lossPercent = 0;
        } else {
            result.lossPercent = (balanceBefore - balanceAfter) * 1e18 / balanceBefore;
            result.earningsPercent = 0;
        }

        return result;
    }

    function _dealAndApprove(IStabilityVault vault, address user, uint amount_) internal returns (
        address[] memory assets,
        uint[] memory amounts
    ) {
        assets = vault.assets();
        amounts = new uint[](assets.length);
        amounts[0] = amount_ == 0
            ? 10 ** IERC20Metadata(assets[0]).decimals()
            : amount_;

        deal(assets[0], address(this), amounts[0]);

        vm.prank(user);
        IERC20(assets[0]).approve(address(vault), amounts[0]);

        return (assets, amounts);
    }

    function _saveResults(TestResult[] memory results) internal {
        string memory fileName = "./tmp/CVault.Upgrade.Batch.Sonic.results.csv";
        string memory content = "VaultAddress;VaultName;Success;TotalGasConsumed;LossPercent(1000=1%);EarningsPercent(1000=1%)\n";
        for (uint i = 0; i < results.length; i++) {

            content = string(abi.encodePacked(
                content,
                Strings.toHexString(VAULT_UNDER_TEST[i]), ";",
                IStabilityVault(VAULT_UNDER_TEST[i]).symbol(), ";",
                results[i].success ? "1" : "0", ";",
                Strings.toString(results[i].totalGasConsumed), ";",
                Strings.toString(results[i].lossPercent * 100_000 / 1e18), ";",
                Strings.toString(results[i].earningsPercent * 100_000 / 1e18), "\n"
            ));
        }
        vm.writeFile(fileName, content);
    }
    //endregion ---------------------- Auxiliary functions

    //region ---------------------- Helpers
    function _upgradeCVault(address vault_) internal {
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
        factory.upgradeVaultProxy(address(vault_));
    }

    function _upgradeVaultStrategy(address vault_) internal {
        IStrategy strategy = IVault(payable(vault_)).strategy();
        if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.SILO)) {
            _upgradeSiloStrategy(address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.SILO_FARM)) {
            _upgradeSiloFarmStrategy(address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.SILO_MANAGED_FARM)) {
            _upgradeSiloManagedFarmStrategy(address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.ICHI_SWAPX_FARM)) {
            _upgradeIchiSwapxFarmStrategy(address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.SILO_ADVANCED_LEVERAGE)) {
            _upgradeSiALStrategy(address(strategy));
        } else {
            console.log("Error: strategy is not upgraded", strategy.strategyLogicId());
        }
    }

    function _upgradeSiloStrategy(address strategyAddress) internal {
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

    function _upgradeSiloFarmStrategy(address strategyAddress) internal {
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

    function _upgradeSiloManagedFarmStrategy(address strategyAddress) internal {
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

    function _upgradeIchiSwapxFarmStrategy(address strategyAddress) internal {
        address strategyImplementation = address(new IchiSwapXFarmStrategy());

        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.ICHI_SWAPX_FARM,
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

    function _upgradeSiALStrategy(address strategyAddress) internal {
        address strategyImplementation = address(new SiloAdvancedLeverageStrategy());

        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.SILO_ADVANCED_LEVERAGE,
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
    //endregion ---------------------- Helpers

}