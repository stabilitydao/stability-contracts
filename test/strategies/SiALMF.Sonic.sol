// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IWrappedMetaVault} from "../../src/interfaces/IWrappedMetaVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IFarmingStrategy} from "../../src/interfaces/IFarmingStrategy.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {ISilo} from "../../src/integrations/silo/ISilo.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {UniversalTest} from "../base/UniversalTest.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";

contract SiloALMFStrategyTest is SonicSetup, UniversalTest {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    uint public constant FARM_META_USD_USDC_53 = 53;
    uint public constant FARM_META_USD_SCUSD_54 = 54;
    uint public constant FARM_METAS_S_55 = 55;
    uint public constant REVERT_NO = 0;
    uint public constant REVERT_NOT_ENOUGH_LIQUIDITY = 1;
    uint public constant REVERT_INSUFFICIENT_BALANCE = 2;
    address internal _currentMetaVault;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        // vm.rollFork(34471950); // Jun-17-2025 09:08:37 AM +UTC
        vm.rollFork(36717785); // Jul-01-2025 01:21:29 PM +UTC
        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;
    }

    function testSiALMFSonic() public universalTest {
        _addStrategy(FARM_META_USD_USDC_53);
        _addStrategy(FARM_META_USD_SCUSD_54);
//        _addStrategy(FARM_METAS_S_55);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO_ALMF_FARM,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }

    //region --------------------------------------- Pre-deposit checkers
    function _preDeposit() internal override {
        uint farmId = _currentFarmId();
        if (farmId == FARM_META_USD_USDC_53 || farmId == FARM_META_USD_SCUSD_54) {
            _currentMetaVault = SonicConstantsLib.METAVAULT_metaUSD;
        } else if (farmId == FARM_METAS_S_55) {
            _currentMetaVault = SonicConstantsLib.METAVAULT_metaS;
        } else {
            revert("Unknown farmId");
        }

        _upgradeMetaVault(address(PLATFORM), _currentMetaVault);

        vm.prank(IPlatform(PLATFORM).multisig());
        IMetaVault(_currentMetaVault).changeWhitelist(currentStrategy, true);

        if (farmId == FARM_META_USD_USDC_53) {
            _checkMaxDepositAssets_All();
        } else if (farmId == FARM_META_USD_SCUSD_54) {
            // farm FARM_META_USD_SCUSD_54 uses Balancer V3 vault
            // we cannot put unlimited flash loan on its balance - we get arithmetic underflow inside sendTo
            _checkMaxDepositAssets_MaxDeposit_LimitedFlash();
            _checkMaxDepositAssets_AmountMoreThanMaxDeposit_LimitedFlash();
        } else {
            _checkMaxDepositAssets_All();
        }
    }

    /// @notice Ensure that the value returned by SiloALMFStrategy.maxDepositAssets is not unlimited.
    /// Ensure that we can deposit max amount and that we CAN'T deposit more than max amount.
    function _checkMaxDepositAssets_All() internal {
        console.log("_checkMaxDepositAssets_MaxDeposit_UnlimitedFlash");
        _checkMaxDepositAssets_MaxDeposit_UnlimitedFlash();
        console.log("_checkMaxDepositAssets_AmountMoreThanMaxDeposit_UnlimitedFlash");
        _checkMaxDepositAssets_AmountMoreThanMaxDeposit_UnlimitedFlash();
        console.log("_checkMaxDepositAssets_MaxDeposit_LimitedFlash");
        _checkMaxDepositAssets_MaxDeposit_LimitedFlash();
        console.log("_checkMaxDepositAssets_AmountMoreThanMaxDeposit_LimitedFlash");
        _checkMaxDepositAssets_AmountMoreThanMaxDeposit_LimitedFlash();
    }

    function _checkMaxDepositAssets_MaxDeposit_UnlimitedFlash() internal {
        IStrategy strategy = IStrategy(currentStrategy);

        // ---------------------------- try to deposit maxDeposit - unlimited flash loan is available
        uint snapshot = vm.snapshot();
        _setUpFlashLoanVault(2e12, false);
        uint[] memory maxDepositAssets = strategy.maxDepositAssets();
        _tryToDeposit(strategy, maxDepositAssets, REVERT_NO);
        vm.revertToState(snapshot);
    }

    function _checkMaxDepositAssets_AmountMoreThanMaxDeposit_UnlimitedFlash() internal {
        IStrategy strategy = IStrategy(currentStrategy);

        // ---------------------------- try to deposit maxDeposit + 1% - unlimited flash loan is available
        uint snapshot = vm.snapshot();
        _setUpFlashLoanVault(2e12, true);
        uint[] memory maxDepositAssets = strategy.maxDepositAssets();
        for (uint i = 0; i < maxDepositAssets.length; i++) {
           maxDepositAssets[i] = maxDepositAssets[i] * 101 / 100;
        }
        _tryToDeposit(strategy, maxDepositAssets, REVERT_NOT_ENOUGH_LIQUIDITY);
        vm.revertToState(snapshot);
    }

    function _checkMaxDepositAssets_MaxDeposit_LimitedFlash() internal {
        IStrategy strategy = IStrategy(currentStrategy);

        // ---------------------------- try to deposit maxDeposit with limited flash loan
        uint snapshot = vm.snapshot();
        _setUpFlashLoanVault(0, false);
        uint[] memory maxDepositAssets = strategy.maxDepositAssets();
        _tryToDeposit(strategy, maxDepositAssets, REVERT_NO);
        vm.revertToState(snapshot);
    }

    function _checkMaxDepositAssets_AmountMoreThanMaxDeposit_LimitedFlash() internal {
        IStrategy strategy = IStrategy(currentStrategy);

        // ---------------------------- try to deposit maxDeposit + 1% with limited flash loan
        uint snapshot = vm.snapshot();
        _setUpFlashLoanVault(0, false);
        uint[] memory maxDepositAssets = strategy.maxDepositAssets();
        for (uint i = 0; i < maxDepositAssets.length; i++) {
            maxDepositAssets[i] = maxDepositAssets[i] * 101 / 100;
        }
        _tryToDeposit(strategy, maxDepositAssets, REVERT_INSUFFICIENT_BALANCE);
        vm.revertToState(snapshot);
    }
    //region --------------------------------------- Pre-deposit checkers

    //region --------------------------------------- Internal logic
    function _currentFarmId() internal view returns (uint) {
        return IFarmingStrategy(currentStrategy).farmId();
    }

    function _setUpFlashLoanVault(uint additionalAmount, bool useAlgebraIfPossible) internal {
        uint farmId = _currentFarmId();
        if (farmId == FARM_META_USD_USDC_53) {
            address pool = useAlgebraIfPossible
                ? SonicConstantsLib.POOL_ALGEBRA_WS_USDC
                : SonicConstantsLib.POOL_SHADOW_CL_USDC_WETH;
            // Set up flash loan vault for the strategy
            _setFlashLoanVault(
                ILeverageLendingStrategy(currentStrategy),
                pool,
                pool,
                useAlgebraIfPossible
                    ? uint(ILeverageLendingStrategy.FlashLoanKind.AlgebraV4_3)
                    : uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2)
            );
            if (additionalAmount != 0) {
                // Add additional amount to the flash loan vault to avoid insufficient balance
                deal(SonicConstantsLib.TOKEN_USDC, pool, additionalAmount);
            }
        } else if (farmId == FARM_META_USD_SCUSD_54) {
            _setFlashLoanVault(
                ILeverageLendingStrategy(currentStrategy),
                SonicConstantsLib.BEETS_VAULT_V3,
                SonicConstantsLib.BEETS_VAULT_V3,
                uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1)
            );
            if (additionalAmount != 0) {
                // Add additional amount to the flash loan vault to avoid insufficient balance
                deal(SonicConstantsLib.TOKEN_scUSD, SonicConstantsLib.BEETS_VAULT_V3, additionalAmount);
            }
        } else if (farmId == FARM_METAS_S_55) {
            _setFlashLoanVault(
                ILeverageLendingStrategy(currentStrategy),
                SonicConstantsLib.BEETS_VAULT,
                SonicConstantsLib.BEETS_VAULT,
                uint(ILeverageLendingStrategy.FlashLoanKind.Default_0)
            );
            if (additionalAmount != 0) {
                // Add additional amount to the flash loan vault to avoid insufficient balance
                deal(SonicConstantsLib.TOKEN_wS, SonicConstantsLib.BEETS_VAULT, additionalAmount);
            }
        } else {
            revert("Unknown farmId");
        }

    }

    function _tryToDeposit(IStrategy strategy, uint[] memory amounts_, uint revertKind) internal {
        // ----------------------------- Transfer deposit amount to the strategy
        IWrappedMetaVault wrappedMetaVault = IWrappedMetaVault(
            strategy.assets()[0] == SonicConstantsLib.WRAPPED_METAVAULT_metaUSD
                ? SonicConstantsLib.WRAPPED_METAVAULT_metaUSD
                : SonicConstantsLib.WRAPPED_METAVAULT_metaS
        );
        console.log("wrappedMetaVault", address(wrappedMetaVault));
        console.log("asset", strategy.assets()[0]);

        _dealAndApprove(address(this), currentStrategy, strategy.assets(), amounts_);
        vm.prank(address(this));
        wrappedMetaVault.transfer(address(strategy), amounts_[0]);

        // ----------------------------- Try to deposit assets to the strategy
        address vault = address(strategy.vault());
        if (revertKind == REVERT_NOT_ENOUGH_LIQUIDITY) {
            vm.expectRevert(ISilo.NotEnoughLiquidity.selector);
        }
        if (revertKind == REVERT_INSUFFICIENT_BALANCE) {
            vm.expectRevert(IControllable.InsufficientBalance.selector);
        }
        vm.prank(vault);
        strategy.depositAssets(amounts_);
    }

    function _dealAndApprove(address user, address spender, address[] memory assets, uint[] memory amounts) internal {
        for (uint j; j < assets.length; ++j) {
            if (assets[j] == SonicConstantsLib.WRAPPED_METAVAULT_metaUSD) {
                _getMetaTokensOnBalance(address(this), amounts[j], true, SonicConstantsLib.WRAPPED_METAVAULT_metaUSD);
            } else if (assets[j] == SonicConstantsLib.WRAPPED_METAVAULT_metaS) {
                _getMetaTokensOnBalance(address(this), amounts[j], true, SonicConstantsLib.WRAPPED_METAVAULT_metaS);
            } else {
                deal(assets[j], user, amounts[j]);
            }

            vm.prank(user);
            IERC20(assets[j]).approve(spender, amounts[j]);
        }
    }

    function _getMetaTokensOnBalance(
        address user,
        uint amountMetaVaultTokens,
        bool wrap,
        address wrappedMetaVault_
    ) internal {
        IMetaVault metaVault = IMetaVault(IWrappedMetaVault(wrappedMetaVault_).metaVault());
        address asset = address(metaVault) == SonicConstantsLib.METAVAULT_metaUSD
            ? SonicConstantsLib.TOKEN_USDC
            : SonicConstantsLib.TOKEN_wS;

        // we don't know exact amount of USDC required to receive exact amountMetaVaultTokens
        // so we deposit a bit large amount of USDC
        address[] memory _assets = metaVault.assetsForDeposit();
        uint[] memory amountsMax = new uint[](1);
        amountsMax[0] = address(metaVault) == SonicConstantsLib.METAVAULT_metaUSD
            ? 2 * amountMetaVaultTokens / 1e12
            : 2 * amountMetaVaultTokens;

        deal(asset, user, amountsMax[0]);

        console.log("deposit.metaVault", address(metaVault), IERC20(asset).balanceOf(user));
        vm.startPrank(user);
        IERC20(asset).approve(
            address(metaVault),
            IERC20(asset).balanceOf(user)
        );
        metaVault.depositAssets(_assets, amountsMax, 0, user);
        vm.roll(block.number + 6);
        vm.stopPrank();

        console.log("wrap");
        if (wrap) {
            vm.startPrank(user);
            IWrappedMetaVault wrappedMetaVault = IWrappedMetaVault(wrappedMetaVault_);
            metaVault.approve(address(wrappedMetaVault), metaVault.balanceOf(user));
            wrappedMetaVault.deposit(metaVault.balanceOf(user), user, 0);
            vm.stopPrank();

            vm.roll(block.number + 6);
        }
    }
    //endregion --------------------------------------- Internal logic

    //region --------------------------------------- Helper functions
    function _upgradeMetaVault(address platform, address metaVault_) internal {
        IMetaVaultFactory metaVaultFactory = IMetaVaultFactory(IPlatform(platform).metaVaultFactory());
        address multisig = IPlatform(platform).multisig();

        // Upgrade MetaVault to the new implementation
        address vaultImplementation = address(new MetaVault());
        vm.prank(multisig);
        metaVaultFactory.setMetaVaultImplementation(vaultImplementation);
        address[] memory metaProxies = new address[](1);
        metaProxies[0] = address(metaVault_);
        vm.prank(multisig);
        metaVaultFactory.upgradeMetaProxies(metaProxies);
    }

    function _setFlashLoanVault(
        ILeverageLendingStrategy strategy,
        address vaultC,
        address vaultB,
        uint kind
    ) internal {
        address multisig = IPlatform(platform).multisig();

        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();
        params[10] = kind;
        addresses[0] = vaultC;
        addresses[1] = vaultB;

        vm.prank(multisig);
        strategy.setUniversalParams(params, addresses);
    }
    //endregion --------------------------------------- Helper functions
}
