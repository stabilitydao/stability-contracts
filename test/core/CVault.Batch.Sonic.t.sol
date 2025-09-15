// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IchiSwapXFarmStrategy} from "../../src/strategies/IchiSwapXFarmStrategy.sol";
import {SiloAdvancedLeverageStrategy} from "../../src/strategies/SiloAdvancedLeverageStrategy.sol";
import {SiloManagedFarmStrategy} from "../../src/strategies/SiloManagedFarmStrategy.sol";
import {SiloStrategy} from "../../src/strategies/SiloStrategy.sol";
import {SiloFarmStrategy} from "../../src/strategies/SiloFarmStrategy.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IPool} from "../../src/integrations/aave/IPool.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {console, Test} from "forge-std/Test.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {AlgebraV4Adapter} from "../../src/adapters/AlgebraV4Adapter.sol";
import {IAToken} from "../../src/integrations/aave/IAToken.sol";
import {BeetsStableFarm} from "../../src/strategies/BeetsStableFarm.sol";
import {BeetsWeightedFarm} from "../../src/strategies/BeetsWeightedFarm.sol";
import {EqualizerFarmStrategy} from "../../src/strategies/EqualizerFarmStrategy.sol";
import {SwapXFarmStrategy} from "../../src/strategies/SwapXFarmStrategy.sol";
import {GammaUniswapV3MerklFarmStrategy} from "../../src/strategies/GammaUniswapV3MerklFarmStrategy.sol";
import {ALMShadowFarmStrategy} from "../../src/strategies/ALMShadowFarmStrategy.sol";
import {SiloLeverageStrategy} from "../../src/strategies/SiloLeverageStrategy.sol";
import {AaveStrategy} from "../../src/strategies/AaveStrategy.sol";
import {AaveMerklFarmStrategy} from "../../src/strategies/AaveMerklFarmStrategy.sol";
import {CompoundV2Strategy} from "../../src/strategies/CompoundV2Strategy.sol";
import {EulerStrategy} from "../../src/strategies/EulerStrategy.sol";
import {SiloALMFStrategy} from "../../src/strategies/SiloALMFStrategy.sol";

/// @notice Test all deployed vaults on given/current block and save summary report to "./tmp/CVault.Upgrade.Batch.Sonic.results.csv"
contract CVaultBatchSonicSkipOnCiTest is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;

    /// @dev This block is used if there is no SONIC_VAULT_BATCH_BLOCK env var set
    uint public constant FORK_BLOCK = 44990313; // Aug-29-2025 09:15:29 AM +UTC

    IFactory public factory;
    address public multisig;
    uint public selectedBlock;

    uint public constant RESULT_FAIL = 0;
    uint public constant RESULT_SUCCESS = 1;
    uint public constant RESULT_SKIPPED = 2;
    uint public constant ERROR_TYPE_DEPOSIT = 1;
    uint public constant ERROR_TYPE_WITHDRAW = 2;

    /// @notice OS is not supported by deal
    address public constant HOLDER_TOKEN_OS = 0xA7bC226C9586DcD93FF1b0B038C04e89b37C8fa7;

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

    constructor() {
        // ---------------- select block for test
        uint _block = vm.envOr("VAULT_BATCH_TEST_SONIC_BLOCK", uint(FORK_BLOCK));
        if (_block == 0) {
            // use latest block if VAULT_BATCH_TEST_SONIC_BLOCK is set to 0
            vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        } else {
            // use block from VAULT_BATCH_TEST_SONIC_BLOCK or pre-defined block if VAULT_BATCH_TEST_SONIC_BLOCK is not set
            vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), _block));
        }
        selectedBlock = block.number;

        factory = IFactory(IPlatform(PLATFORM).factory());
        multisig = IPlatform(PLATFORM).multisig();

        // _upgradePlatform(IPlatform(PLATFORM).priceReader());
    }

    function testDepositWithdrawBatch() public {
        address[] memory _deployedVaults = factory.deployedVaults();

        TestResult[] memory results = new TestResult[](_deployedVaults.length);

        console.log(">>>>> Start Batch Sonic CVault upgrade test >>>>>");
        for (uint i = 0; i < _deployedVaults.length; i++) {
            (results[i].vaultTvlUsd,) = IStabilityVault(_deployedVaults[i]).tvl();

            uint status = factory.vaultStatus(_deployedVaults[i]);
            bool skipped;
            if (status != 1) {
                results[i].result = RESULT_SKIPPED;
                results[i].errorReason = "Status is not 1";
            } else if (isExpiredPt(_deployedVaults[i])) {
                results[i].result = RESULT_SKIPPED;
                results[i].errorReason = "PT market is expired";
            } else if (results[i].vaultTvlUsd == 0) {
                results[i].result = RESULT_SKIPPED;
                results[i].errorReason = "Zero tvl";
            } else {
                uint snapshot = vm.snapshotState();
                results[i] = _testDepositWithdrawSingleVault(_deployedVaults[i], true, 0);
                vm.revertToState(snapshot);
            }
            if (skipped) {
                console.log("SKIPPED:", IERC20Metadata(_deployedVaults[i]).symbol(), address(_deployedVaults[i]));
            }
            results[i].status = status;
        }
        console.log("<<<< Finish Batch Sonic CVault upgrade test <<<<");

        {
            uint countFailed;
            uint countSkipped;
            for (uint i = 0; i < results.length; i++) {
                if (results[i].result == RESULT_FAIL) {
                    countFailed++;
                } else if (results[i].result == RESULT_SKIPPED) {
                    countSkipped++;
                }
            }
            console.log(
                "Results: success/failed/skipped",
                _deployedVaults.length - countFailed - countSkipped,
                countFailed,
                countSkipped
            );
        }

        _saveResults(results, _deployedVaults);
    }

    //region ---------------------- Auxiliary tests
    /// @notice Auxiliary test to debug particular vaults
    function testDepositWithdrawSingle() internal {
        // TestResult memory r = _testDepositWithdrawSingleVault(SonicConstantsLib.VAULT_LEV_SIAL_WSTKSCUSD_USDC, false, 100e6);
        // TestResult memory r = _testDepositWithdrawSingleVault(SonicConstantsLib.VAULT_LEV_SIAL_WSTKSCETH_WETH, false, 0.1e18);
        TestResult memory r = _testDepositWithdrawSingleVault(0xb9fDf7ce72AAcE505a5c37Ad4d4F0BaB1fcc2a0D, false, 0);
        showResults(r);
        assertEq(r.result, RESULT_SUCCESS, "Selected vault should pass deposit/withdraw test");
    }

    /// @dev Auxiliary test to set up _deal function
    function testDial() internal {
        address[] memory _deployedVaults = factory.deployedVaults();
        for (uint i = 0; i < _deployedVaults.length; i++) {
            uint status = factory.vaultStatus(_deployedVaults[i]);
            if (status == 1) {
                IStabilityVault _vault = IStabilityVault(_deployedVaults[i]);
                address[] memory assets = _vault.assets();

                console.log("Vault, asset", _deployedVaults[i], IERC20Metadata(_deployedVaults[i]).symbol(), assets[0]);
                _dealAndApprove(_vault, address(this), 0);
                console.log("done");
            }
        }
    }
    //endregion ---------------------- Auxiliary tests

    //region ---------------------- Auxiliary functions
    function _testDepositWithdrawSingleVault(
        address vault_,
        bool catchError,
        uint amount_
    ) internal returns (TestResult memory result) {
        IStabilityVault vault = IStabilityVault(vault_);

        _upgradeCVault(vault_);
        _upgradeVaultStrategy(vault_);
        _setUpVault(vault_);

        result = _testDepositWithdraw(vault, catchError, amount_);

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
        IStabilityVault vault,
        bool catchError,
        uint amount_
    ) internal returns (TestResult memory result) {
        uint balance0 = IERC20(vault.assets()[0]).balanceOf(address(this));
        (result.vaultTvlUsd,) = vault.tvl();

        // --------------- prepare amount to deposit
        (address[] memory assets, uint[] memory depositAmounts) = _dealAndApprove(vault, address(this), amount_);
        uint balanceBefore = IERC20(assets[0]).balanceOf(address(this));

        // --------------- deposit
        uint gas0 = gasleft();
        if (catchError) {
            try vault.depositAssets(assets, depositAmounts, 0, address(this)) {
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
            vault.depositAssets(assets, depositAmounts, 0, address(this));
            result.result = RESULT_SUCCESS;
        }
        result.totalGasConsumed = gas0 - gasleft();

        vm.roll(block.number + 6);

        // --------------- withdraw
        if (result.result == RESULT_SUCCESS) {
            uint amountToWithdraw = vault.balanceOf(address(this));

            gas0 = gasleft();
            if (catchError) {
                try vault.withdrawAssets(assets, amountToWithdraw, new uint[](assets.length)) {
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
                vault.withdrawAssets(assets, amountToWithdraw, new uint[](1));
                result.result = RESULT_FAIL;
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

    function _dealAndApprove(
        IStabilityVault vault,
        address user,
        uint amount_
    ) internal returns (address[] memory assets, uint[] memory amounts) {
        assets = vault.assets();

        amounts = new uint[](assets.length);
        for (uint i; i < assets.length; ++i) {
            amounts[i] = amount_ == 0 ? _getDefaultAmountToDeposit(assets[i]) : amount_;
            //console.log("Dealing", assets[i], amounts[i]);
            if (assets[i] == SonicConstantsLib.TOKEN_AUSDC) {
                _dealAave(assets[i], address(this), amounts[i]);
            } else if (assets[i] == SonicConstantsLib.TOKEN_OS) {
                _transferAmountFromHolder(assets[i], address(this), amounts[i], HOLDER_TOKEN_OS);
            } else {
                deal(assets[i], address(this), amounts[i]);
            }

            vm.prank(user);
            IERC20(assets[i]).approve(address(vault), amounts[i]);
        }

        return (assets, amounts);
    }

    function _saveResults(TestResult[] memory results, address[] memory vaults_) internal {
        // --------------- first line - block number
        string memory content = string(abi.encodePacked("BlockNumber", ";", Strings.toString(selectedBlock), "\n"));
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
        vm.writeFile("./tmp/CVault.Batch.Sonic.results.csv", content);
    }

    function showResults(TestResult memory r) internal pure {
        console.log("Success:", r.result);
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

    //region ---------------------- Deal assets
    /// @notice Deal doesn't work with aave tokens. So, deal the asset and mint aTokens instead.
    /// @dev https://github.com/foundry-rs/forge-std/issues/140
    function _dealAave(address aToken_, address to, uint amount) internal {
        IPool pool = IPool(IAToken(aToken_).POOL());

        address asset = IAToken(aToken_).UNDERLYING_ASSET_ADDRESS();

        deal(asset, to, amount);

        vm.prank(to);
        IERC20(asset).approve(address(pool), amount);

        vm.prank(to);
        pool.deposit(asset, amount, to, 0);
    }

    /// @dev Attempt of dealing OS token gives the error: [FAIL: stdStorage find(StdStorage): Failed to write value.]
    /// Let's try to deal wS instead and swap it to OS
    function _transferAmountFromHolder(address token_, address to, uint amount, address holder_) internal {
        uint balance = IERC20(token_).balanceOf(holder_);

        uint amountToTransfer = Math.min(amount, balance);

        vm.prank(holder_);
        IERC20(token_).transfer(to, amountToTransfer);
    }
    //endregion ---------------------- Deal assets

    //region ---------------------- Set up vaults behavior

    /// @notice PT market is expired and doesn't allow deposit, so it should be skipped in the test
    function isExpiredPt(address vault_) internal pure returns (bool ret) {
        ret = vault_ == SonicConstantsLib.VAULT_LEV_SIAL_ASONUSDC_SCUSD_14AUG2025
            || vault_ == 0x03645841df5f71dc2c86bbdB15A97c66B34765b6 // C-PT-wstkscUSD-29MAY2025-SA
            || vault_ == 0x376ddBa57C649CEe95F93f827C61Af95ca519164 // C-PT-wstkscUSD-29MAY2025-SA
            || vault_ == 0xadE710c52Cf4AB8bE1ffD292Ca266A6a4E49B2D2 // C-PT-wstkscETH-29MAY2025-SA
            || vault_ == 0x425f26609e2309b9AB72cbF95092834e33B29A8a //  C-PT-wOS-29MAY2025-SA
            || vault_ == 0x59Ab350EE281a24a6D75d789E0264F2d4C3913b5 //  C-PT-wstkscETH-29MAY2025-SAL
            || vault_ == 0x6F5791B0D0CF656fF13b476aF62afb93138AeAd9 //  C-PT-Silo-20-USDC.e-17JUL2025-SAL
            || vault_ == 0x24288C119CeA7ddF6d2267B61b19C0e971EBAd40 //  C-PT-aSonUSDC-14AUG2025-SAL
            || vault_ == 0xb2D7f55037A303B9f6AF0729C1183B43FBb3CBb6 //  C-PT-Silo-46-scUSD-14AUG2025-SAL
            || vault_ == 0x716ab48eC4054cf2330167C80a65B27cd57E09Cf; //  C-PT-stS-29MAY2025-SAL
    }

    /// @dev Make any set up actions before deposit/withdraw test
    function _setUpVault(address vault_) internal {
        //        // ---------------- fix routes for VAULT_LEV_SIAL_WSTKSCUSD_USDC using beets-v3 adapter
        //        if (vault_ == SonicConstantsLib.VAULT_LEV_SIAL_WSTKSCUSD_USDC) {
        //            ISwapper swapper = ISwapper(IPlatform(PLATFORM).swapper());
        //
        //            ISwapper.PoolData[] memory pools = new ISwapper.PoolData[](2);
        //            pools[0] = ISwapper.PoolData({
        //                pool: SonicConstantsLib.POOL_BEETS_V3_BOOSTED_USDC_WSTKSCUSD_SCUSD,
        //                ammAdapter: (IPlatform(PLATFORM).ammAdapter(keccak256(bytes(AmmAdapterIdLib.BALANCER_V3_STABLE)))).proxy,
        //                tokenIn: address(SonicConstantsLib.TOKEN_WSTKSCUSD),
        //                tokenOut: address(SonicConstantsLib.SILO_VAULT_46_SCUSD)
        //            });
        //            pools[1] = ISwapper.PoolData({
        //                pool: SonicConstantsLib.SILO_VAULT_46_SCUSD,
        //                ammAdapter: (IPlatform(PLATFORM).ammAdapter(keccak256(bytes(AmmAdapterIdLib.ERC_4626)))).proxy,
        //                tokenIn: address(SonicConstantsLib.SILO_VAULT_46_SCUSD),
        //                tokenOut: address(SonicConstantsLib.TOKEN_SCUSD)
        //            });
        //
        //            vm.prank(multisig);
        //            ISwapper(swapper).addPools(pools, true);
        //        }
        //
        //        // ---------------- fix routes for VAULT_LEV_SIAL_WSTKSCETH_WETH using beets-v3 adapter
        //        if (vault_ == SonicConstantsLib.VAULT_LEV_SIAL_WSTKSCETH_WETH) {
        //            ISwapper swapper = ISwapper(IPlatform(PLATFORM).swapper());
        //
        //            ISwapper.PoolData[] memory pools = new ISwapper.PoolData[](2);
        //            pools[0] = ISwapper.PoolData({
        //                pool: SonicConstantsLib.POOL_BEETS_V3_BOOSTED_WETH_SCETH_WSTKSCETH,
        //                ammAdapter: (IPlatform(PLATFORM).ammAdapter(keccak256(bytes(AmmAdapterIdLib.BALANCER_V3_STABLE)))).proxy,
        //                tokenIn: address(SonicConstantsLib.TOKEN_WSTKSCETH),
        //                tokenOut: address(SonicConstantsLib.SILO_VAULT_47_BSCETH)
        //            });
        //            pools[1] = ISwapper.PoolData({
        //                pool: SonicConstantsLib.SILO_VAULT_47_BSCETH,
        //                ammAdapter: (IPlatform(PLATFORM).ammAdapter(keccak256(bytes(AmmAdapterIdLib.ERC_4626)))).proxy,
        //                tokenIn: address(SonicConstantsLib.SILO_VAULT_47_BSCETH),
        //                tokenOut: address(SonicConstantsLib.TOKEN_SCETH)
        //            });
        //
        //            vm.prank(multisig);
        //            ISwapper(swapper).addPools(pools, true);
        //        }

        // ILeverageLendingStrategy _strategy = ILeverageLendingStrategy(address(IVault(vault_).strategy()));
    }

    function _getDefaultAmountToDeposit(address asset_) internal view returns (uint) {
        if (
            asset_ == SonicConstantsLib.TOKEN_WETH || asset_ == SonicConstantsLib.TOKEN_ATETH
                || asset_ == SonicConstantsLib.TOKEN_SCETH || asset_ == SonicConstantsLib.TOKEN_STKSCETH
                || asset_ == SonicConstantsLib.TOKEN_WSTKSCETH
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
    //endregion ---------------------- Helpers

    //region ---------------------- Upgrade strategies
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
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.BEETS_STABLE_FARM)) {
            _upgradeBeetsStable(address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.BEETS_WEIGHTED_FARM)) {
            _upgradeBeetsWeightedFarm(address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.EQUALIZER_FARM)) {
            _upgradeEqualizerFarm(address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.SWAPX_FARM)) {
            _upgradeSwapXFarm(address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.GAMMA_UNISWAPV3_MERKL_FARM)) {
            _upgradeGammaUniswapV3MerklFarm(address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.ALM_SHADOW_FARM)) {
            _upgradeAlmShadowFarm(address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.SILO_LEVERAGE)) {
            _upgradeSiloLeverage(address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.AAVE)) {
            _upgradeAave(address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.AAVE_MERKL_FARM)) {
            _upgradeAaveMerklFarm(address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.COMPOUND_V2)) {
            _upgradeCompoundV2(address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.EULER)) {
            _upgradeEuler(address(strategy));
        } else if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.SILO_ALMF_FARM)) {
            _upgradeSiALMF(address(strategy));
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
                farming: false,
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
                farming: false,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeBeetsStable(address strategyAddress) internal {
        address strategyImplementation = address(new BeetsStableFarm());

        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.BEETS_STABLE_FARM,
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

    function _upgradeBeetsWeightedFarm(address strategyAddress) internal {
        address strategyImplementation = address(new BeetsWeightedFarm());

        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.BEETS_WEIGHTED_FARM,
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

    function _upgradeEqualizerFarm(address strategyAddress) internal {
        address strategyImplementation = address(new EqualizerFarmStrategy());

        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.EQUALIZER_FARM,
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

    function _upgradeSwapXFarm(address strategyAddress) internal {
        address strategyImplementation = address(new SwapXFarmStrategy());

        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.SWAPX_FARM,
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

    function _upgradeGammaUniswapV3MerklFarm(address strategyAddress) internal {
        address strategyImplementation = address(new GammaUniswapV3MerklFarmStrategy());

        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.GAMMA_UNISWAPV3_MERKL_FARM,
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

    function _upgradeAlmShadowFarm(address strategyAddress) internal {
        address strategyImplementation = address(new ALMShadowFarmStrategy());

        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.ALM_SHADOW_FARM,
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

    function _upgradeSiloLeverage(address strategyAddress) internal {
        address strategyImplementation = address(new SiloLeverageStrategy());

        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.SILO_LEVERAGE,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: false,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeAave(address strategyAddress) internal {
        address strategyImplementation = address(new AaveStrategy());

        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.AAVE,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: false,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeAaveMerklFarm(address strategyAddress) internal {
        address strategyImplementation = address(new AaveMerklFarmStrategy());

        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.AAVE_MERKL_FARM,
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

    function _upgradeCompoundV2(address strategyAddress) internal {
        address strategyImplementation = address(new CompoundV2Strategy());

        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.COMPOUND_V2,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: false,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeEuler(address strategyAddress) internal {
        address strategyImplementation = address(new EulerStrategy());

        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.EULER,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: false,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeSiALMF(address strategyAddress) internal {
        address strategyImplementation = address(new SiloALMFStrategy());

        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.SILO_ALMF_FARM,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: false,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(strategyAddress);
    }
    //endregion ---------------------- Upgrade strategies
}
