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
import {Swapper} from "../../src/core/Swapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {console, Test} from "forge-std/Test.sol";
import {IStrategyProxy} from "../../src/interfaces/IStrategyProxy.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {AlgebraV4Adapter} from "../../src/adapters/AlgebraV4Adapter.sol";

/// @notice Test multiple vaults on given/current block and save summary report to the file
contract CVaultUpgradeBatchSonicTest is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;

    /// @dev This block is used if there is no SONIC_VAULT_BATCH_BLOCK env var set
    uint public constant FORK_BLOCK = 44570424; // Aug-26-2025 07:45:25 AM +UTC
    // uint public constant FORK_BLOCK = 43911991; // Aug-21-2025 04:58:57 AM +UTC

    IFactory public factory;
    address public multisig;

    address[2] internal VAULT_UNDER_TEST;

    address public constant HOLDER_1 = 0x23b8Cc22C4c82545F4b451B11E2F17747A730810;
    address public constant HOLDER_2 = 0x98a0efc622cDc86B38484Ce6A6729606D26e500e;
    address public constant HOLDER_3 = 0xA534e734446CAe195d65d920fA47305F0dC55934;
    address public constant HOLDER_4 = 0x64758ef549B0e7714C2c69aE6097810D3c970d69;
    address public constant HOLDER_5 = 0x2a1842baC18058078F682e1996f763480081174A;

    struct TestResult {
        bool success;
        /// @dev Summary of gas consumed during deposit, withdraw and (probably) any other vault actions in the test
        uint totalGasConsumed;
        /// @dev Total losses of the user in percents after all vault operations, 100% = 1e18; 0 for negative losses
        uint lossPercent;
        /// @dev Total earnings of the user in percents after all vault operations, 100% = 1e18; 0 for negative earnings
        uint earningsPercent;

        uint amountDeposited;
        uint amountWithdrawn;
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

        // _upgradePlatform(IPlatform(PLATFORM).priceReader());

        // ---------------- create list of vaults to test
        VAULT_UNDER_TEST = [
            SonicConstantsLib.VAULT_LEV_SiAL_wstkscUSD_USDC,
            SonicConstantsLib.VAULT_LEV_SiAL_wstkscETH_WETH
            // SonicConstantsLib.VAULT_LEV_SiAL_aSonUSDC_scUSD_14AUG2025  // expired
        ];
    }

    function testDepositWithdrawBatch() public {
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
        TestResult memory r = _testDepositWithdrawSingleVault(VAULT_UNDER_TEST[0], false, 100e6);
        // TestResult memory r = _testDepositWithdrawSingleVault(VAULT_UNDER_TEST[1], false, 0.1e18);
        showResults(r);
        assertEq(r.success, true, "Selected vault should pass deposit/withdraw test");
    }

    function testWithdrawOnly() public {
        address vault_ = VAULT_UNDER_TEST[0];
        IStabilityVault vault = IStabilityVault(vault_);

        ILeverageLendingStrategy _strategy = ILeverageLendingStrategy(address(IVault(vault_).strategy()));

//        vm.prank(multisig);
//        _strategy.setTargetLeveragePercent(5000);

        (uint[] memory params, address[] memory addresses) = _strategy.getUniversalParams();
        for (uint i; i < params.length; i++) {
            console.log("param", i, params[i]);
        }
        for (uint i; i < addresses.length; i++) {
            console.log("address", i, addresses[i]);
        }

        _testWithdrawOnly(VAULT_UNDER_TEST[0], HOLDER_1);
        _testWithdrawOnly(VAULT_UNDER_TEST[0], HOLDER_2);
        _testWithdrawOnly(VAULT_UNDER_TEST[0], HOLDER_3);
        _testWithdrawOnly(VAULT_UNDER_TEST[0], HOLDER_4);
        _testWithdrawOnly(VAULT_UNDER_TEST[0], HOLDER_5);
    }


    //region ---------------------- Auxiliary functions
    function _testWithdrawOnly(address vault_, address holder_) internal {
        IStabilityVault vault = IStabilityVault(vault_);

        _upgradeCVault(vault_);
        _upgradeVaultStrategy(vault_);
        _setUpVault(vault_);

        address[] memory assets = vault.assets();
        uint amountToWithdraw = vault.balanceOf(holder_);

        vm.prank(holder_);
        uint[] memory withdrawn = vault.withdrawAssets(assets, amountToWithdraw, new uint[](1));
        console.log("!!!!! withdrawn", withdrawn[0], holder_);
    }

    function _testDepositWithdrawSingleVault(address vault_, bool catchError, uint amount_) internal returns (TestResult memory result) {
        IStabilityVault vault = IStabilityVault(vault_);

        _upgradeCVault(vault_);
        _upgradeVaultStrategy(vault_);
        _setUpVault(vault_);

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
        uint balance0 = IERC20(vault.assets()[0]).balanceOf(address(this));

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
            uint amountToWithdraw = vault.balanceOf(address(this));

            gas0 = gasleft();
            if (catchError) {
                try vault.withdrawAssets(assets, amountToWithdraw, new uint[](1)) {
                    result.success = true;
                } catch {
                    result.success = false;
                }
            } else {
                vault.withdrawAssets(assets, amountToWithdraw, new uint[](1));
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

        result.amountDeposited = depositAmounts[0];
        result.amountWithdrawn = balanceAfter > balance0 ? balanceAfter - balance0 : 0;

        return result;
    }

    function _dealAndApprove(IStabilityVault vault, address user, uint amount_) internal returns (
        address[] memory assets,
        uint[] memory amounts
    ) {
        assets = vault.assets();
        amounts = new uint[](assets.length);
        amounts[0] = amount_ == 0
            ? _getDefaultAmountToDeposit(assets[0])
            : amount_;

        deal(assets[0], address(this), amounts[0]);

        vm.prank(user);
        IERC20(assets[0]).approve(address(vault), amounts[0]);

        return (assets, amounts);
    }

    function _saveResults(TestResult[] memory results) internal {
        string memory fileName = "./tmp/CVault.Upgrade.Batch.Sonic.results.csv";
        string memory content = "VaultAddress;VaultName;Success;TotalGasConsumed;AmountDeposited;AmountWithdrawn;LossPercent(1000=1%);EarningsPercent(1000=1%)\n";
        for (uint i = 0; i < results.length; i++) {

            content = string(abi.encodePacked(
                content,
                Strings.toHexString(VAULT_UNDER_TEST[i]), ";",
                IStabilityVault(VAULT_UNDER_TEST[i]).symbol(), ";",
                results[i].success ? "1" : "0", ";",
                Strings.toString(results[i].totalGasConsumed), ";",
                Strings.toString(results[i].amountDeposited), ";",
                Strings.toString(results[i].amountWithdrawn), ";",
                Strings.toString(results[i].lossPercent * 100_000 / 1e18), ";",
                Strings.toString(results[i].earningsPercent * 100_000 / 1e18), "\n"
            ));
        }
        vm.writeFile(fileName, content);
    }

    function showResults(TestResult memory r) internal pure {
        console.log("Success:", r.success);
        console.log("TotalGasConsumed:", r.totalGasConsumed);
        console.log("LossPercent(1000=1%):", r.lossPercent * 100_000 / 1e18);
        console.log("EarningsPercent(1000=1%):", r.earningsPercent * 100_000 / 1e18);
        console.log("AmountDeposited:", r.amountDeposited);
        console.log("AmountWithdrawn:", r.amountWithdrawn);
    }

    function _adjustParamsSetDepositParam0(ILeverageLendingStrategy strategy, uint depositParam0_) internal {
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

    //region ---------------------- Set up vaults behavior
    /// @dev Make any set up actions before deposit/withdraw test
    function _setUpVault(address vault_) internal {

        if (false) {
            // ---------------- fix routes for VAULT_LEV_SiAL_wstkscUSD_USDC using fixed AlgebraV4-adapter
            if (vault_ == SonicConstantsLib.VAULT_LEV_SiAL_wstkscUSD_USDC) {
                // try to fix routes
                // Currently we have a route: wstkscUSD => scUSD => USDC but there is no liquidity in the shadow pool
                // Set up new route: wstkscUSD => bUSDCe20 => USDC
                ISwapper swapper = ISwapper(IPlatform(PLATFORM).swapper());
                bytes32 _hash = keccak256(bytes(AmmAdapterIdLib.ALGEBRA_V4));

                ISwapper.PoolData[] memory pools = new ISwapper.PoolData[](1);
                pools[0] = ISwapper.PoolData({
                    pool: SonicConstantsLib.POOL_SWAPX_CL_bUSDCe20_wstkscUSD,
                    ammAdapter: (IPlatform(PLATFORM).ammAdapter(_hash)).proxy,
                    tokenIn: address(SonicConstantsLib.TOKEN_wstkscUSD),
                    tokenOut: address(SonicConstantsLib.TOKEN_bUSDCe20)
                });

                vm.prank(multisig);
                ISwapper(swapper).addPools(pools, true);
            }
        }
        // ---------------- fix routes for VAULT_LEV_SiAL_wstkscUSD_USDC using beets-v3 adapter
        if (vault_ == SonicConstantsLib.VAULT_LEV_SiAL_wstkscUSD_USDC) {
            ISwapper swapper = ISwapper(IPlatform(PLATFORM).swapper());

            ISwapper.PoolData[] memory pools = new ISwapper.PoolData[](2);
            pools[0] = ISwapper.PoolData({
                pool: SonicConstantsLib.POOL_BEETS_V3_BOOSTED_USDC_wstkscUSD_scUSD,
                ammAdapter: (IPlatform(PLATFORM).ammAdapter(keccak256(bytes(AmmAdapterIdLib.BALANCER_V3_STABLE)))).proxy,
                tokenIn: address(SonicConstantsLib.TOKEN_wstkscUSD),
                tokenOut: address(SonicConstantsLib.SILO_VAULT_46_scUSD)
            });
            pools[1] = ISwapper.PoolData({
                pool: SonicConstantsLib.SILO_VAULT_46_scUSD,
                ammAdapter: (IPlatform(PLATFORM).ammAdapter(keccak256(bytes(AmmAdapterIdLib.ERC_4626)))).proxy,
                tokenIn: address(SonicConstantsLib.SILO_VAULT_46_scUSD),
                tokenOut: address(SonicConstantsLib.TOKEN_scUSD)
            });

            vm.prank(multisig);
            ISwapper(swapper).addPools(pools, true);

            {
                ILeverageLendingStrategy _strategy = ILeverageLendingStrategy(address(IVault(vault_).strategy()));
            }
        }

        // ---------------- fix routes for VAULT_LEV_SiAL_wstkscETH_WETH using beets-v3 adapter
        if (vault_ == SonicConstantsLib.VAULT_LEV_SiAL_wstkscETH_WETH) {
            ISwapper swapper = ISwapper(IPlatform(PLATFORM).swapper());

            ISwapper.PoolData[] memory pools = new ISwapper.PoolData[](2);
            pools[0] = ISwapper.PoolData({
                pool: SonicConstantsLib.POOL_BEETS_V3_BOOSTED_WETH_scETH_wstkscETH,
                ammAdapter: (IPlatform(PLATFORM).ammAdapter(keccak256(bytes(AmmAdapterIdLib.BALANCER_V3_STABLE)))).proxy,
                tokenIn: address(SonicConstantsLib.TOKEN_wstkscETH),
                tokenOut: address(SonicConstantsLib.SILO_VAULT_47_bscETH)
            });
            pools[1] = ISwapper.PoolData({
                pool: SonicConstantsLib.SILO_VAULT_47_bscETH,
                ammAdapter: (IPlatform(PLATFORM).ammAdapter(keccak256(bytes(AmmAdapterIdLib.ERC_4626)))).proxy,
                tokenIn: address(SonicConstantsLib.SILO_VAULT_47_bscETH),
                tokenOut: address(SonicConstantsLib.TOKEN_scETH)
            });

            vm.prank(multisig);
            ISwapper(swapper).addPools(pools, true);
        }
    }

    function _getDefaultAmountToDeposit(address asset_) internal view returns (uint) {
        if (
            asset_ == SonicConstantsLib.TOKEN_wETH
            || asset_ == SonicConstantsLib.TOKEN_atETH
            || asset_ == SonicConstantsLib.TOKEN_scETH
            || asset_ == SonicConstantsLib.TOKEN_stkscETH
            || asset_ == SonicConstantsLib.TOKEN_wstkscETH
        ) {
            return 1e18;
        }

        return 10 * 10 ** IERC20Metadata(asset_).decimals();
    }

    //endregion ---------------------- Set up vaults behavior

    //region ---------------------- Helpers
    function _upgradePlatform(address priceReader_) internal {
        // we need to skip 1 day to update the swapper
        // but we cannot simply skip 1 day, because the silo oracle will start to revert with InvalidPrice
        // vm.warp(block.timestamp - 86400);
        rewind(86400);

        IPlatform platform = IPlatform(IControllable(priceReader_).platform());

        address[] memory proxies = new address[](1);
        address[] memory implementations = new address[](1);

        //proxies[0] = address(priceReader_);
        // proxies[0] = platform.swapper();
        proxies[0] = platform.ammAdapter(keccak256(bytes(AmmAdapterIdLib.ALGEBRA_V4))).proxy;

        //implementations[0] = address(new PriceReader());
        // implementations[0] = address(new Swapper());
        implementations[0] = address(new AlgebraV4Adapter());

        //vm.prank(multisig);
        // platform.cancelUpgrade();

        vm.startPrank(multisig);
        platform.announcePlatformUpgrade("2025.07.22-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }

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