// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IWrappedMetaVault} from "../../src/interfaces/IWrappedMetaVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
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
    uint public constant REVERT_NO = 0;
    uint public constant REVERT_NOT_ENOUGH_LIQUIDITY = 1;
    uint public constant REVERT_INSUFFICIENT_BALANCE = 2;

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
        _addStrategy(53);
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

    function _preDeposit() internal override {
        _upgradeMetaVault(address(PLATFORM), SonicConstantsLib.METAVAULT_metaUSD);

        vm.prank(IPlatform(PLATFORM).multisig());
        IMetaVault(SonicConstantsLib.METAVAULT_metaUSD).changeWhitelist(currentStrategy, true);

        _checkMaxDepositAssets();
    }

    /// @notice Ensure that the value returned by SiloALMFStrategy.maxDepositAssets is not unlimited.
    /// Ensure that we can deposit max amount and that we CAN'T deposit more than max amount.
    function _checkMaxDepositAssets() internal {
        IStrategy strategy = IStrategy(currentStrategy);

        // ---------------------------- try to deposit maxDeposit - unlimited flash loan is available
        uint snapshot = vm.snapshot();
        _setUpFlashLoanVault(2e12);
        uint[] memory maxDepositAssets = strategy.maxDepositAssets();
        _tryToDeposit(strategy, maxDepositAssets, REVERT_NO);
        vm.revertToState(snapshot);

        // ---------------------------- try to deposit maxDeposit + 1% - unlimited flash loan is available
        snapshot = vm.snapshot();
        _setUpFlashLoanVault(2e12);
        maxDepositAssets = strategy.maxDepositAssets();
        for (uint i = 0; i < maxDepositAssets.length; i++) {
            maxDepositAssets[i] = maxDepositAssets[i] * 101 / 100;
        }
        _tryToDeposit(strategy, maxDepositAssets, REVERT_NOT_ENOUGH_LIQUIDITY);
        vm.revertToState(snapshot);

        // ---------------------------- try to deposit maxDeposit with limited flash loan
        snapshot = vm.snapshot();
        _setUpFlashLoanVault(0);
        maxDepositAssets = strategy.maxDepositAssets();
        _tryToDeposit(strategy, maxDepositAssets, REVERT_NO);
        vm.revertToState(snapshot);

        // ---------------------------- try to deposit maxDeposit + 1% with limited flash loan
        snapshot = vm.snapshot();
        _setUpFlashLoanVault(0);
        maxDepositAssets = strategy.maxDepositAssets();
        for (uint i = 0; i < maxDepositAssets.length; i++) {
            maxDepositAssets[i] = maxDepositAssets[i] * 101 / 100;
        }
        _tryToDeposit(strategy, maxDepositAssets, REVERT_INSUFFICIENT_BALANCE);
        vm.revertToState(snapshot);
    }

    //region --------------------------------------- Internal logic
    function _setUpFlashLoanVault(uint additionalAmount) internal {
        // Set up flash loan vault for the strategy
        _setFlashLoanVault(
            ILeverageLendingStrategy(currentStrategy),
            SonicConstantsLib.POOL_SHADOW_CL_USDC_WETH,
            SonicConstantsLib.POOL_SHADOW_CL_USDC_WETH,
            uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2)
        );

        if (additionalAmount != 0) {
            // Add additional amount to the flash loan vault to avoid insufficient balance
            deal(SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.POOL_SHADOW_CL_USDC_WETH, additionalAmount);
        }
    }

    function _tryToDeposit(IStrategy strategy, uint[] memory amounts_, uint revertKind) internal {
        // ----------------------------- Transfer deposit amount to the strategy
        _dealAndApprove(address(this), currentStrategy, strategy.assets(), amounts_);
        vm.prank(address(this));
        IMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD).transfer(address(strategy), amounts_[0]);

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
                _getMetaUsdOnBalance(address(this), amounts[j], true);
                console.log(
                    "Dealing and approving metaUSD",
                    amounts[0],
                    IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD).balanceOf(address(this))
                );
            } else {
                console.log("Dealing and approving", assets[j], amounts[j]);
                deal(assets[j], user, amounts[j]);
            }

            vm.prank(user);
            IERC20(assets[j]).approve(spender, amounts[j]);
        }
    }

    function _getMetaUsdOnBalance(address user, uint amountMetaVaultTokens, bool wrap) internal {
        IMetaVault metaVault = IMetaVault(SonicConstantsLib.METAVAULT_metaUSD);

        // we don't know exact amount of USDC required to receive exact amountMetaVaultTokens
        // so we deposit a bit large amount of USDC
        address[] memory _assets = metaVault.assetsForDeposit();
        uint[] memory amountsMax = new uint[](1);
        amountsMax[0] = 2 * amountMetaVaultTokens / 1e12;

        deal(SonicConstantsLib.TOKEN_USDC, user, amountsMax[0]);

        vm.startPrank(user);
        IERC20(SonicConstantsLib.TOKEN_USDC).approve(
            address(metaVault), IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(user)
        );
        metaVault.depositAssets(_assets, amountsMax, 0, user);
        vm.roll(block.number + 6);
        vm.stopPrank();

        if (wrap) {
            vm.startPrank(user);
            IWrappedMetaVault wrappedMetaVault = IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_metaUSD);
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
