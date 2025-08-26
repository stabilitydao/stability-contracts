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
contract SialUpgradeMaxLtvSonic is Test {
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
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), uint(FORK_BLOCK)));

        factory = IFactory(IPlatform(PLATFORM).factory());
        multisig = IPlatform(PLATFORM).multisig();

        // _upgradePlatform(IPlatform(PLATFORM).priceReader());
    }

    function testWithdrawOnly() public {
        address vault_ = SonicConstantsLib.VAULT_LEV_SiAL_wstkscUSD_USDC;

        _testWithdrawOnly(vault_, HOLDER_1, 436983127);
        _testWithdrawOnly(vault_, HOLDER_2, 783121065);
        _testWithdrawOnly(vault_, HOLDER_3, 2484744085);
        _testWithdrawOnly(vault_, HOLDER_4, 1734149530);
        _testWithdrawOnly(vault_, HOLDER_5, 26080160);
    }

    //region ---------------------- Auxiliary functions
    function _testWithdrawOnly(address vault_, address holder_, uint expectedAmount) internal {
        IStabilityVault vault = IStabilityVault(vault_);

        _upgradeCVault(vault_);
        _upgradeVaultStrategy(vault_);
        _setUpVault(vault_);

        address[] memory assets = vault.assets();
        uint amountToWithdraw = vault.balanceOf(holder_);

        vm.prank(holder_);
        uint[] memory withdrawn = vault.withdrawAssets(assets, amountToWithdraw, new uint[](1));
        // console.log("!!!!! withdrawn", withdrawn[0], holder_, expectedAmount  * 100 / 104);
        assertGt(withdrawn[0], expectedAmount * 100 / 104, "max 4% loss");
    }

    //endregion ---------------------- Auxiliary functions

    //region ---------------------- Set up vaults behavior
    /// @dev Make any set up actions before deposit/withdraw test
    function _setUpVault() internal {
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
        if (CommonLib.eq(strategy.strategyLogicId(), StrategyIdLib.SILO_ADVANCED_LEVERAGE)) {
            _upgradeSiALStrategy(address(strategy));
        } else {
            console.log("Error: strategy is not upgraded", strategy.strategyLogicId());
        }
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
