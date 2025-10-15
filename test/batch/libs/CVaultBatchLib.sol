// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SiloManagedMerklFarmStrategy} from "../../../src/strategies/SiloManagedMerklFarmStrategy.sol";
import {IchiSwapXFarmStrategy} from "../../../src/strategies/IchiSwapXFarmStrategy.sol";
import {SiloAdvancedLeverageStrategy} from "../../../src/strategies/SiloAdvancedLeverageStrategy.sol";
import {SiloManagedFarmStrategy} from "../../../src/strategies/SiloManagedFarmStrategy.sol";
import {SiloStrategy} from "../../../src/strategies/SiloStrategy.sol";
import {SiloFarmStrategy} from "../../../src/strategies/SiloFarmStrategy.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {CommonLib} from "../../../src/core/libs/CommonLib.sol";
import {CVault} from "../../../src/core/vaults/CVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../../../src/interfaces/IFactory.sol";
import {IPlatform} from "../../../src/interfaces/IPlatform.sol";
import {IStrategy} from "../../../src/interfaces/IStrategy.sol";
import {ILeverageLendingStrategy} from "../../../src/interfaces/ILeverageLendingStrategy.sol";
import {IStabilityVault} from "../../../src/interfaces/IStabilityVault.sol";
import {IVault} from "../../../src/interfaces/IVault.sol";
import {IControllable} from "../../../src/interfaces/IControllable.sol";
import {StrategyIdLib} from "../../../src/strategies/libs/StrategyIdLib.sol";
import {VaultTypeLib} from "../../../src/core/libs/VaultTypeLib.sol";
import {SiloAdvancedLib} from "../../../src/strategies/libs/SiloAdvancedLib.sol";
import {BeetsStableFarm} from "../../../src/strategies/BeetsStableFarm.sol";
import {BeetsWeightedFarm} from "../../../src/strategies/BeetsWeightedFarm.sol";
import {EqualizerFarmStrategy} from "../../../src/strategies/EqualizerFarmStrategy.sol";
import {SwapXFarmStrategy} from "../../../src/strategies/SwapXFarmStrategy.sol";
import {GammaUniswapV3MerklFarmStrategy} from "../../../src/strategies/GammaUniswapV3MerklFarmStrategy.sol";
import {ALMShadowFarmStrategy} from "../../../src/strategies/ALMShadowFarmStrategy.sol";
import {SiloLeverageStrategy} from "../../../src/strategies/SiloLeverageStrategy.sol";
import {AaveStrategy} from "../../../src/strategies/AaveStrategy.sol";
import {AaveMerklFarmStrategy} from "../../../src/strategies/AaveMerklFarmStrategy.sol";
import {CompoundV2Strategy} from "../../../src/strategies/CompoundV2Strategy.sol";
import {EulerStrategy} from "../../../src/strategies/EulerStrategy.sol";
import {SiloALMFStrategy} from "../../../src/strategies/SiloALMFStrategy.sol";
import {console, Vm} from "forge-std/Test.sol";
import {EulerMerklFarmStrategy} from "../../../src/strategies/EulerMerklFarmStrategy.sol";

/// @notice Shared functions for CVaultBatch-tests
library CVaultBatchLib {
    uint public constant RESULT_FAIL = 0;
    uint public constant RESULT_SUCCESS = 1;
    uint public constant RESULT_SKIPPED = 2;
    uint public constant ERROR_TYPE_DEPOSIT = 1;
    uint public constant ERROR_TYPE_WITHDRAW = 2;

    struct TestResult {
        uint result;
        string errorReason;
        /// @dev 0 - no error, 1 - deposit, 2 - withdraw
        uint errorType;
        /// @dev Summary of gas consumed during deposit, withdraw and (probably) any other vault actions in the test
        uint totalGasConsumed;
        /// @dev Total losses of the user in percents after all vault operations, 100% = 1e18; 0 for negative losses
        uint lossPercent;
        /// @dev Total earnings of the user in percents after all vault operations, 100% = 1e18; 0 for negative earnings
        uint earningsPercent;
        uint amountDeposited;
        uint amountWithdrawn;
        uint status;
        uint vaultTvlUsd;
    }

    //region ---------------------- Auxiliary functions
    function _testDepositWithdrawSingleVault(
        Vm vm,
        address vault_,
        bool catchError,
        address[] memory assets_,
        uint[] memory depositAmounts_
    ) internal returns (TestResult memory result) {
        IStabilityVault vault = IStabilityVault(vault_);

        result = _testDepositWithdraw(vm, vault, catchError, assets_, depositAmounts_);

        if (result.result == RESULT_SUCCESS) {
            console.log(
                "Success: vault, gas, earning/loss %",
                vault.symbol(),
                result.totalGasConsumed,
                result.earningsPercent > 0
                    ? result.earningsPercent * 100_000 / 1e18
                    : result.lossPercent * 100_000 / 1e18
            );
        } else {
            console.log("Failed:", vault.symbol(), address(vault));
        }

        return result;
    }

    function _testDepositWithdraw(
        Vm vm,
        IStabilityVault vault,
        bool catchError,
        address[] memory assets_,
        uint[] memory depositAmounts_
    ) internal returns (TestResult memory result) {
        uint balance0 = IERC20(vault.assets()[0]).balanceOf(address(this));
        (result.vaultTvlUsd,) = vault.tvl();

        // --------------- prepare amount to deposit
        // assume that {depositAmounts_} of {assets_} are already deposited on address(this) here
        uint balanceBefore = IERC20(assets_[0]).balanceOf(address(this));

        // --------------- deposit
        uint gas0 = gasleft();
        if (catchError) {
            try vault.depositAssets(assets_, depositAmounts_, 0, address(this)) {
                result.result = RESULT_SUCCESS;
            } catch Error(string memory reason) {
                result.result = RESULT_FAIL;
                result.errorType = ERROR_TYPE_DEPOSIT;
                result.errorReason = reason;
            } catch (bytes memory reason) {
                result.result = RESULT_FAIL;
                result.errorType = ERROR_TYPE_DEPOSIT;
                result.errorReason =
                    string(abi.encodePacked("Deposit custom error: ", Strings.toHexString(uint32(bytes4(reason)), 4)));
            }
        } else {
            vault.depositAssets(assets_, depositAmounts_, 0, address(this));
            result.result = RESULT_SUCCESS;
        }
        result.totalGasConsumed = gas0 - gasleft();

        vm.roll(block.number + 6);

        // --------------- withdraw
        if (result.result == RESULT_SUCCESS) {
            uint amountToWithdraw = vault.balanceOf(address(this));

            gas0 = gasleft();
            if (catchError) {
                try vault.withdrawAssets(assets_, amountToWithdraw, new uint[](assets_.length)) {
                    result.result = RESULT_SUCCESS;
                } catch Error(string memory reason) {
                    result.result = RESULT_FAIL;
                    result.errorReason = reason;
                    result.errorType = ERROR_TYPE_WITHDRAW;
                } catch (bytes memory reason) {
                    result.result = RESULT_FAIL;
                    result.errorType = ERROR_TYPE_DEPOSIT;
                    result.errorReason = string(
                        abi.encodePacked("Withdraw custom error: ", Strings.toHexString(uint32(bytes4(reason)), 4))
                    );
                }
            } else {
                vault.withdrawAssets(assets_, amountToWithdraw, new uint[](1));
                result.result = RESULT_FAIL;
            }
            result.totalGasConsumed = gas0 - gasleft();
        }

        // --------------- check results
        uint balanceAfter = IERC20(assets_[0]).balanceOf(address(this));
        if (balanceAfter > balanceBefore) {
            result.earningsPercent = (balanceAfter - balanceBefore) * 1e18 / balanceBefore;
            result.lossPercent = 0;
        } else {
            result.lossPercent = (balanceBefore - balanceAfter) * 1e18 / balanceBefore;
            result.earningsPercent = 0;
        }

        result.amountDeposited = depositAmounts_[0];
        result.amountWithdrawn = balanceAfter > balance0 ? balanceAfter - balance0 : 0;

        return result;
    }

    function _testWithdrawSingle(
        Vm vm,
        IStabilityVault vault,
        address holder_,
        uint amount_
    ) internal returns (uint withdrawn) {
        // _upgradeVaultStrategy(address(vault));

        uint amountToWithdraw = amount_ == 0 ? vault.balanceOf(holder_) : amount_;
        console.log("Max withdraw", vault.maxWithdraw(holder_));
        console.log("To withdraw", amountToWithdraw);

        address[] memory _assets = vault.assets();

        vm.prank(holder_);
        return vault.withdrawAssets(_assets, amountToWithdraw, new uint[](1))[0];
    }

    function _saveResults(
        Vm vm,
        TestResult[] memory results,
        address[] memory vaults_,
        uint selectedBlock_,
        string memory fnOut
    ) internal {
        // --------------- first line - block number
        string memory content = string(abi.encodePacked("BlockNumber", ";", Strings.toString(selectedBlock_), "\n"));
        // --------------- second line - header
        content = string(
            abi.encodePacked(
                content,
                "Status;VaultAddress;VaultName;Result;TotalGasConsumed;AmountDeposited;AmountWithdrawn;LossPercent(1000=1%);EarningsPercent(1000=1%);ErrorText;ErrorType;TVL\n"
            )
        );

        //
        for (uint i = 0; i < results.length; i++) {
            content = string(
                abi.encodePacked(
                    content,
                    Strings.toString(results[i].status),
                    ";",
                    Strings.toHexString(vaults_[i]),
                    ";",
                    IStabilityVault(vaults_[i]).symbol(),
                    ";",
                    results[i].result == RESULT_SUCCESS
                        ? "success"
                        : results[i].result == RESULT_FAIL ? "fail" : "skipped",
                    ";"
                )
            );

            content = string(
                abi.encodePacked(
                    content,
                    Strings.toString(results[i].totalGasConsumed),
                    ";",
                    Strings.toString(results[i].amountDeposited),
                    ";",
                    Strings.toString(results[i].amountWithdrawn),
                    ";",
                    Strings.toString(results[i].lossPercent * 100_000 / 1e18),
                    ";",
                    Strings.toString(results[i].earningsPercent * 100_000 / 1e18),
                    ";",
                    results[i].errorReason,
                    ";",
                    results[i].errorType == 0
                        ? ""
                        : results[i].errorType == ERROR_TYPE_DEPOSIT
                            ? "deposit"
                            : results[i].errorType == ERROR_TYPE_WITHDRAW ? "withdraw" : "unknown",
                    ";",
                    Strings.toString(results[i].vaultTvlUsd),
                    "\n"
                )
            );
        }
        if (!vm.exists("./tmp")) {
            vm.createDir("./tmp", true);
        }
        vm.writeFile(string.concat("./tmp/", fnOut), content);
    }

    function showResults(TestResult memory r) internal pure {
        console.log("Success:", r.result);
        console.log("TotalGasConsumed:", r.totalGasConsumed);
        console.log("LossPercent(1000=1%):", r.lossPercent * 100_000 / 1e18);
        console.log("EarningsPercent(1000=1%):", r.earningsPercent * 100_000 / 1e18);
        console.log("AmountDeposited:", r.amountDeposited);
        console.log("AmountWithdrawn:", r.amountWithdrawn);
    }

    function _adjustParamsSetDepositParam0(Vm vm, ILeverageLendingStrategy strategy, uint depositParam0_) internal {
        address multisig = IPlatform(IControllable(address(strategy)).platform()).multisig();

        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();
        for (uint i; i < params.length; i++) {
            console.log("param", i, params[i]);
        }
        for (uint i; i < addresses.length; i++) {
            console.log("address", i, addresses[i]);
        }

        params[0] = depositParam0_;

        vm.prank(multisig);
        strategy.setUniversalParams(params, addresses);
    }

    //endregion ---------------------- Auxiliary functions

    //region ---------------------- Deal assets

    /// @dev Attempt of dealing OS token gives the error: [FAIL: stdStorage find(StdStorage): Failed to write value.]
    /// Let's try to deal wS instead and swap it to OS
    function _transferAmountFromHolder(Vm vm, address token_, address to, uint amount, address holder_) internal {
        uint balance = IERC20(token_).balanceOf(holder_);

        uint amountToTransfer = Math.min(amount, balance);

        vm.prank(holder_);
        /// forge-lint: disable-next-line
        IERC20(token_).transfer(to, amountToTransfer);
    }

    //endregion ---------------------- Deal assets

    //region ---------------------- Set up vaults behavior

    /// @notice PT market is expired and doesn't allow deposit, so it should be skipped in the test
    function isExpiredPt(address vault_) internal view returns (bool ret) {
        string memory strategyLogicId = IVault(vault_).strategy().strategyLogicId();
        if (CommonLib.eq(strategyLogicId, StrategyIdLib.SILO_ADVANCED_LEVERAGE)) {
            ILeverageLendingStrategy _strategy = ILeverageLendingStrategy(address(IVault(vault_).strategy()));
            (uint[] memory params,) = _strategy.getUniversalParams();
            if (params[1] == SiloAdvancedLib.COLLATERAL_IS_PT_EXPIRED_MARKET) {
                return true;
            }
        }

        return false;
    }

    //endregion ---------------------- Set up vaults behavior

    //region ---------------------- Helpers
    function _upgradeCVault(Vm vm, address vault_) internal {
        address multisig = IPlatform(IControllable(address(IVault(vault_).strategy())).platform()).multisig();
        IFactory factory = IFactory(IPlatform(IControllable(address(IVault(vault_).strategy())).platform()).factory());

        // deploy new impl and upgrade
        address vaultImplementation = address(new CVault());
        vm.prank(multisig);
        factory.setVaultImplementation(VaultTypeLib.COMPOUNDING, vaultImplementation);
        factory.upgradeVaultProxy(address(vault_));
    }

    /// @notice add this to be excluded from coverage report
    function test() public {}

    //endregion ---------------------- Helpers

    //region ---------------------- Upgrade strategies
    function _upgradeVaultStrategy(Vm vm, address vault_) internal {
        address multisig = IPlatform(IControllable(address(IVault(vault_).strategy())).platform()).multisig();
        IFactory factory = IFactory(IPlatform(IControllable(address(IVault(vault_).strategy())).platform()).factory());

        IStrategy strategy = IVault(payable(vault_)).strategy();
        if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.SILO)) {
            _upgradeSiloStrategy(vm, multisig, factory, address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.SILO_FARM)) {
            _upgradeSiloFarmStrategy(vm, multisig, factory, address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.SILO_MANAGED_FARM)) {
            _upgradeSiloManagedFarmStrategy(vm, multisig, factory, address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.ICHI_SWAPX_FARM)) {
            _upgradeIchiSwapxFarmStrategy(vm, multisig, factory, address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.SILO_ADVANCED_LEVERAGE)) {
            _upgradeSiALStrategy(vm, multisig, factory, address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.BEETS_STABLE_FARM)) {
            _upgradeBeetsStable(vm, multisig, factory, address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.BEETS_WEIGHTED_FARM)) {
            _upgradeBeetsWeightedFarm(vm, multisig, factory, address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.EQUALIZER_FARM)) {
            _upgradeEqualizerFarm(vm, multisig, factory, address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.SWAPX_FARM)) {
            _upgradeSwapXFarm(vm, multisig, factory, address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.GAMMA_UNISWAPV3_MERKL_FARM)) {
            _upgradeGammaUniswapV3MerklFarm(vm, multisig, factory, address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.ALM_SHADOW_FARM)) {
            _upgradeAlmShadowFarm(vm, multisig, factory, address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.SILO_LEVERAGE)) {
            _upgradeSiloLeverage(vm, multisig, factory, address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.AAVE)) {
            _upgradeAave(vm, multisig, factory, address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.AAVE_MERKL_FARM)) {
            _upgradeAaveMerklFarm(vm, multisig, factory, address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.COMPOUND_V2)) {
            _upgradeCompoundV2(vm, multisig, factory, address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.EULER)) {
            _upgradeEuler(vm, multisig, factory, address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.EULER_MERKL_FARM)) {
            _upgradeEulerMerklFarm(vm, multisig, factory, address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.SILO_ALMF_FARM)) {
            _upgradeSiALMF(vm, multisig, factory, address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.SILO_MANAGED_MERKL_FARM)) {
            _upgradeSiMMF(vm, multisig, factory, address(strategy));
        } else {
            console.log("Error: strategy is not upgraded", strategy.strategyLogicId());
        }
    }

    function _upgradeSiloStrategy(Vm vm, address multisig, IFactory factory, address strategyAddress) internal {
        address strategyImplementation = address(new SiloStrategy());

        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.SILO, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeSiloFarmStrategy(Vm vm, address multisig, IFactory factory, address strategyAddress) internal {
        address strategyImplementation = address(new SiloFarmStrategy());
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.SILO_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeSiloManagedFarmStrategy(
        Vm vm,
        address multisig,
        IFactory factory,
        address strategyAddress
    ) internal {
        address strategyImplementation = address(new SiloManagedFarmStrategy());

        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.SILO_MANAGED_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeIchiSwapxFarmStrategy(
        Vm vm,
        address multisig,
        IFactory factory,
        address strategyAddress
    ) internal {
        address strategyImplementation = address(new IchiSwapXFarmStrategy());

        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.ICHI_SWAPX_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeSiALStrategy(Vm vm, address multisig, IFactory factory, address strategyAddress) internal {
        address strategyImplementation = address(new SiloAdvancedLeverageStrategy());

        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.SILO_ADVANCED_LEVERAGE, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeBeetsStable(Vm vm, address multisig, IFactory factory, address strategyAddress) internal {
        address strategyImplementation = address(new BeetsStableFarm());

        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.BEETS_STABLE_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeBeetsWeightedFarm(Vm vm, address multisig, IFactory factory, address strategyAddress) internal {
        address strategyImplementation = address(new BeetsWeightedFarm());

        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.BEETS_WEIGHTED_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeEqualizerFarm(Vm vm, address multisig, IFactory factory, address strategyAddress) internal {
        address strategyImplementation = address(new EqualizerFarmStrategy());

        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.EQUALIZER_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeSwapXFarm(Vm vm, address multisig, IFactory factory, address strategyAddress) internal {
        address strategyImplementation = address(new SwapXFarmStrategy());

        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.SWAPX_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeGammaUniswapV3MerklFarm(
        Vm vm,
        address multisig,
        IFactory factory,
        address strategyAddress
    ) internal {
        address strategyImplementation = address(new GammaUniswapV3MerklFarmStrategy());

        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.GAMMA_UNISWAPV3_MERKL_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeAlmShadowFarm(Vm vm, address multisig, IFactory factory, address strategyAddress) internal {
        address strategyImplementation = address(new ALMShadowFarmStrategy());

        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.ALM_SHADOW_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeSiloLeverage(Vm vm, address multisig, IFactory factory, address strategyAddress) internal {
        address strategyImplementation = address(new SiloLeverageStrategy());

        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.SILO_LEVERAGE, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeAave(Vm vm, address multisig, IFactory factory, address strategyAddress) internal {
        address strategyImplementation = address(new AaveStrategy());

        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.AAVE, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeAaveMerklFarm(Vm vm, address multisig, IFactory factory, address strategyAddress) internal {
        address strategyImplementation = address(new AaveMerklFarmStrategy());

        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.AAVE_MERKL_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeCompoundV2(Vm vm, address multisig, IFactory factory, address strategyAddress) internal {
        address strategyImplementation = address(new CompoundV2Strategy());

        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.COMPOUND_V2, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeEuler(Vm vm, address multisig, IFactory factory, address strategyAddress) internal {
        address strategyImplementation = address(new EulerStrategy());

        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.EULER, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeEulerMerklFarm(Vm vm, address multisig, IFactory factory, address strategyAddress) internal {
        address strategyImplementation = address(new EulerMerklFarmStrategy());

        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.SILO_ALMF_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeSiALMF(Vm vm, address multisig, IFactory factory, address strategyAddress) internal {
        address strategyImplementation = address(new SiloALMFStrategy());

        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.SILO_ALMF_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeSiMMF(Vm vm, address multisig, IFactory factory, address strategyAddress) internal {
        address strategyImplementation = address(new SiloManagedMerklFarmStrategy());

        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.SILO_MANAGED_MERKL_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }
    //endregion ---------------------- Upgrade strategies
}
