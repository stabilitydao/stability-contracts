// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CVaultBatchLib} from "./libs/CVaultBatchLib.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";
import {Factory} from "../../src/core/Factory.sol";
import {IAToken} from "../../src/integrations/aave/IAToken.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IPool} from "../../src/integrations/aave/IPool.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {console, Test} from "forge-std/Test.sol";

/// @notice Test all deployed vaults on given/current block and save summary report to "./tmp/CVault.Upgrade.Batch.Sonic.results.csv"
contract CVaultBatchSonicSkipOnCiTest is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;

    /// @dev This block is used if there is no SONIC_VAULT_BATCH_BLOCK env var set
    //uint public constant FORK_BLOCK = 47248396; // Sep-18-2025 07:32:40 AM +UTC
    uint public constant FORK_BLOCK = 47714014; // Sep-22-2025 02:38:15 AM +UTC

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

        _upgradePlatform();
    }

    function testDepositWithdrawBatch() public {
        address[] memory _deployedVaults = factory.deployedVaults();

        CVaultBatchLib.TestResult[] memory results = new CVaultBatchLib.TestResult[](_deployedVaults.length);

        console.log(">>>>> Start Batch Sonic CVault upgrade test >>>>>");
        for (uint i = 0; i < _deployedVaults.length; i++) {
            (results[i].vaultTvlUsd,) = IStabilityVault(_deployedVaults[i]).tvl();

            uint status = factory.vaultStatus(_deployedVaults[i]);
            bool skipped;
            if (status != 1) {
                results[i].result = RESULT_SKIPPED;
                results[i].errorReason = "Status is not 1";
            } else if (CVaultBatchLib.isExpiredPt(_deployedVaults[i])) {
                results[i].result = RESULT_SKIPPED;
                results[i].errorReason = "PT market is expired";
            } else if (results[i].vaultTvlUsd == 0) {
                results[i].result = RESULT_SKIPPED;
                results[i].errorReason = "Zero tvl";
            } else {
                uint snapshot = vm.snapshotState();
                (address[] memory assets, uint[] memory depositAmounts) = _dealAndApprove(IStabilityVault(_deployedVaults[i]), address(this), 0);
                results[i] = CVaultBatchLib._testDepositWithdrawSingleVault(vm, _deployedVaults[i], true, assets, depositAmounts);
                vm.revertToState(snapshot);
            }
            if (skipped) {
                console.log("SKIPPED:", IERC20Metadata(_deployedVaults[i]).symbol(), address(_deployedVaults[i]));
            }
            results[i].status = status;
            CVaultBatchLib._saveResults(vm, results, _deployedVaults, selectedBlock);
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

        CVaultBatchLib._saveResults(vm, results, _deployedVaults, selectedBlock);
    }

    //region ---------------------- Auxiliary tests
    /// @notice Auxiliary test to debug particular vaults
    function testDepositWithdrawSingle() internal {
        // TestResult memory r = _testDepositWithdrawSingleVault(SonicConstantsLib.VAULT_LEV_SiAL_wstkscUSD_USDC, false, 100e6);
        // TestResult memory r = _testDepositWithdrawSingleVault(SonicConstantsLib.VAULT_LEV_SiAL_wstkscETH_WETH, false, 0.1e18);
        address vault = 0xb9fDf7ce72AAcE505a5c37Ad4d4F0BaB1fcc2a0D;
        (address[] memory assets, uint[] memory depositAmounts) = _dealAndApprove(IStabilityVault(vault), address(this), 0);
        CVaultBatchLib.TestResult memory r = CVaultBatchLib._testDepositWithdrawSingleVault(vm, vault, false, assets, depositAmounts);
        CVaultBatchLib.showResults(r);
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

    /// @dev Auxiliary test to withdraw from vault by holder
    function testWithdrawSingle() internal {
        uint withdrawn = CVaultBatchLib._testWithdrawSingle(
            vm,
            IStabilityVault(0x4BC62FcF68732eA77ef9Dd72f4EBc1042702bC9D),
            0xe19763bAa197e17A5663F8941177bFBBD31a7ab0,
            23352862707783185
        );
        console.log("Withdrawn", withdrawn);
        assertNotEq(withdrawn, 0, "Withdraw some amount from vault");
    }
    //endregion ---------------------- Auxiliary tests

    //region ---------------------- Auxiliary functions
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
            if (assets[i] == SonicConstantsLib.TOKEN_aUSDC) {
                _dealAave(assets[i], address(this), amounts[i]);
            } else if (assets[i] == SonicConstantsLib.TOKEN_OS) {
                CVaultBatchLib._transferAmountFromHolder(vm, assets[i], address(this), amounts[i], HOLDER_TOKEN_OS);
            } else {
                deal(assets[i], address(this), amounts[i]);
            }

            vm.prank(user);
            IERC20(assets[i]).approve(address(vault), amounts[i]);
        }

        return (assets, amounts);
    }

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

    //endregion ---------------------- Auxiliary functions

    //region ---------------------- Sonic-related functions
    function _getDefaultAmountToDeposit(address asset_) internal view returns (uint) {
        if (
            asset_ == SonicConstantsLib.TOKEN_wETH || asset_ == SonicConstantsLib.TOKEN_atETH
            || asset_ == SonicConstantsLib.TOKEN_scETH || asset_ == SonicConstantsLib.TOKEN_stkscETH
            || asset_ == SonicConstantsLib.TOKEN_wstkscETH
        ) {
            return 1e18;
        }

        return 10 * 10 ** IERC20Metadata(asset_).decimals();
    }
    //endregion ---------------------- Sonic-related functions


    //region ---------------------- Helpers
    function _upgradePlatform() internal {
        // we need to skip 1 day to update the swapper
        // but we cannot simply skip 1 day, because the silo oracle will start to revert with InvalidPrice
        // vm.warp(block.timestamp - 86400);
        rewind(86400);

        IPlatform platform = IPlatform(PLATFORM);

        address[] memory proxies = new address[](1);
        address[] memory implementations = new address[](1);

        //proxies[0] = address(priceReader_);
        proxies[0] = platform.factory();
        //proxies[0] = platform.ammAdapter(keccak256(bytes(AmmAdapterIdLib.ALGEBRA_V4))).proxy;

        //implementations[0] = address(new PriceReader());
        implementations[0] = address(new Factory());
        //implementations[0] = address(new AlgebraV4Adapter());

        //vm.prank(multisig);
        // platform.cancelUpgrade();

        vm.startPrank(multisig);
        platform.announcePlatformUpgrade("2025.07.22-alpha", proxies, implementations);

        skip(1 days);
        platform.upgrade();
        vm.stopPrank();
    }
    //endregion ---------------------- Helpers

}
