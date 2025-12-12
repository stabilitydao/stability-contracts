// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Factory} from "../../src/core/Factory.sol";
import {MetaVault, IMetaVault, IStabilityVault, IPlatform, IPriceReader} from "../../src/core/vaults/MetaVault.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {IWrappedMetaVault} from "../../src/interfaces/IWrappedMetaVault.sol";
import {Platform} from "../../src/core/Platform.sol";
import {Swapper} from "../../src/core/Swapper.sol";
import {PriceReader} from "../../src/core/PriceReader.sol";
import {Proxy} from "../../src/core/proxy/Proxy.sol";
import {ISilo} from "../../src/integrations/silo/ISilo.sol";
import {SiloALMFStrategy} from "../../src/strategies/SiloALMFStrategy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {Test, Vm} from "forge-std/Test.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {WrappedMetaVault} from "../../src/core/vaults/WrappedMetaVault.sol";
import {MetaVaultAdapter} from "../../src/adapters/MetaVaultAdapter.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {SonicFarmMakerLib} from "../../chains/sonic/SonicFarmMakerLib.sol";

/// @notice Create MultiVault with SiALMF-vaults to test maxDeposit()
contract MetaVaultMaxDepositMetaUsdSonicTest is Test {
    // uint public constant FORK_BLOCK = 36795243; // Jul-02-2025 03:38:32 AM +UTC
    uint public constant FORK_BLOCK = 36825191; // Jul-02-2025 09:02:59 AM +UTC
    uint public constant MULTI_VAULT_INDEX = 0;
    uint public constant META_VAULT_INDEX = 1;

    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVaultFactory public metaVaultFactory;
    address[] public metaVaults;
    address[] public wrappedVaults;
    IPriceReader public priceReader;
    address public multisig;
    uint public timestamp0;

    struct Strategy {
        string id;
        address pool;
        uint farmId;
        address[] strategyInitAddresses;
        uint[] strategyInitNums;
    }

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        timestamp0 = block.timestamp;

        // we need to skip 1 day to update the swapper
        // but we cannot simply skip 1 day, because the silo oracle will start to revert with InvalidPrice
        vm.warp(timestamp0 - 86400);
    }

    function setUp() public {
        multisig = IPlatform(PLATFORM).multisig();
        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
        metaVaultFactory = IMetaVaultFactory(SonicConstantsLib.METAVAULT_FACTORY);
        Factory factory = Factory(address(IPlatform(PLATFORM).factory()));

        _upgradePlatform();
        _setupMetaVaultFactory();
        _setupImplementations();
        _updateCVaultImplementation(factory);

        // ------------------------------ Create vaults and strategies
        vm.startPrank(multisig);
        factory.addFarms(_farms());
        {
            IFactory.StrategyAvailableInitParams memory p;
            factory.setStrategyAvailableInitParams(StrategyIdLib.SILO_ALMF_FARM, p);
        }
        factory.setStrategyImplementation(StrategyIdLib.SILO_ALMF_FARM, address(new SiloALMFStrategy()));
        address[] memory _vaults = _createVaultsAndStrategies(factory);
        vm.stopPrank();

        // ------------------------------ Set up whitelist
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        for (uint i; i < _vaults.length; ++i) {
            address strategy = address(IVault(_vaults[i]).strategy());

            vm.prank(IPlatform(PLATFORM).multisig());
            IMetaVault(SonicConstantsLib.METAVAULT_METAUSD).changeWhitelist(strategy, true);

            vm.prank(multisig);
            priceReader.changeWhitelistTransientCache(strategy, true);
        }

        // ------------------------------ Setup swap of metaUSD
        _addAdapter();

        {
            ISwapper swapper = ISwapper(IPlatform(PLATFORM).swapper());

            vm.startPrank(multisig);
            swapper.addPools(_routes(), false);
            vm.stopPrank();
        }

        // ------------------------------ Create meta vaults and wrappers

        metaVaults = new address[](2);
        wrappedVaults = new address[](2);
        uint[] memory _proportions = new uint[](2);

        // metaUSDC: single USDC lending vaults
        string memory vaultType = VaultTypeLib.MULTIVAULT;
        _proportions[0] = 50e16;
        _proportions[1] = 50e16;
        metaVaults[MULTI_VAULT_INDEX] = _deployMetaVaultByMetaVaultFactory(
            vaultType, SonicConstantsLib.TOKEN_USDC, "Stability USDC", "metaUSDC", _vaults, _proportions
        );
        wrappedVaults[MULTI_VAULT_INDEX] = _deployWrapper(metaVaults[MULTI_VAULT_INDEX]);

        // metaUSD: single MultiVault
        vaultType = VaultTypeLib.METAVAULT;
        _vaults = new address[](1);
        _vaults[0] = metaVaults[MULTI_VAULT_INDEX];
        _proportions = new uint[](1);
        _proportions[0] = 100e16;
        metaVaults[META_VAULT_INDEX] = _deployMetaVaultByMetaVaultFactory(
            vaultType, address(0), "Stability USD", "metaUSD", _vaults, _proportions
        );
        wrappedVaults[META_VAULT_INDEX] = _deployWrapper(metaVaults[META_VAULT_INDEX]);

        // ---- Make flash loan unlimited and fees-free to simplify calculations
        _setUpFlashLoanVault(10e12); // add 10 mln USDC and 10 mln scUSD to flash loan vaults

        // ---------------------------------- Set whitelist for transient cache #348
        vm.prank(multisig);
        priceReader.changeWhitelistTransientCache(SonicConstantsLib.METAVAULT_METAUSD, true);

        vm.prank(multisig);
        priceReader.changeWhitelistTransientCache(metaVaults[META_VAULT_INDEX], true);

        // ------------------------------ Make initial deposit to both sub-vaults to avoid first-deposit-small-amount issues
        _initialDeposit();
    }

    //region -------------------------------------------- Test Wrapped Meta Vault
    function testWrappedMetaVaultMaxDeposit() public view {
        IWrappedMetaVault wrappedMulti = IWrappedMetaVault(wrappedVaults[META_VAULT_INDEX]);
        IMetaVault metaVault = IMetaVault(metaVaults[META_VAULT_INDEX]);

        // max deposit amount to MultiVault
        uint maxAmountToDepositMulti = metaVault.maxDeposit(address(this))[0];

        // max deposit amount to wrapped
        uint maxAmountToDepositWrapped = wrappedMulti.maxDeposit(address(this));

        assertNotEq(maxAmountToDepositMulti, type(uint).max, "meta.maxDeposit is limited");
        assertEq(maxAmountToDepositWrapped, type(uint).max, "wrapped.maxDeposit is unlimited");
    }

    function testWrappedMetaVaultDepositMax() public {
        IWrappedMetaVault wrappedMeta = IWrappedMetaVault(wrappedVaults[META_VAULT_INDEX]);
        IMetaVault metaVault = IMetaVault(metaVaults[META_VAULT_INDEX]);

        // ---- Reduce available liquidity in Silo on 99% (to avoid price impact problems during swap of scUSD to USDC)
        _borrowAlmostAllCash(
            ISilo(SonicConstantsLib.SILO_VAULT_121_WMETAUSD), ISilo(SonicConstantsLib.SILO_VAULT_121_USDC), 99_00
        );
        _borrowAlmostAllCash(
            ISilo(SonicConstantsLib.SILO_VAULT_125_WMETAUSD), ISilo(SonicConstantsLib.SILO_VAULT_125_SCUSD), 99_00
        );

        // ------------------------------ Get a lot of metaUSD on balance and deposit them to MetaVault
        {
            uint amountMetaUsd = metaVault.maxDeposit(address(this))[0]; // amount of metaUSD to deposit in embedded MultiVault
            _getMetaUsdOnBalance(address(this), amountMetaUsd, true);

            vm.prank(address(this));
            IERC20(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD).approve(address(metaVault), type(uint).max);

            uint[] memory amountsMax = new uint[](1);
            amountsMax[0] = amountMetaUsd;

            vm.prank(address(this));
            metaVault.depositAssets(metaVault.assetsForDeposit(), amountsMax, 0, address(this));
            vm.roll(block.number + 6);
        }

        // ------------------------------ Get max-deposit for MultiVault
        uint maxAmountToDepositMulti = IMetaVault(metaVaults[MULTI_VAULT_INDEX]).maxDeposit(address(this))[0];

        // ------------------------------ Try to wrap all available MetaVault tokens
        uint amountMetaVaultTokensToDeposit = metaVault.balanceOf(address(this));

        vm.prank(address(this));
        metaVault.approve(address(wrappedMeta), amountMetaVaultTokensToDeposit);

        uint wrappedBalanceBefore = wrappedMeta.balanceOf(address(this));
        uint balanceBefore = metaVault.balanceOf(address(this));

        vm.prank(address(this));
        wrappedMeta.deposit(amountMetaVaultTokensToDeposit, address(this), 0);
        vm.roll(block.number + 6); // we need it because withdraw uses MetaVault.transfer internally

        uint balanceAfter = metaVault.balanceOf(address(this));
        uint wrappedBalanceAfter = wrappedMeta.balanceOf(address(this));

        // ------------------------------ Check results
        assertEq(
            balanceBefore - balanceAfter,
            amountMetaVaultTokensToDeposit,
            "Deposit max possible amount should be successful"
        );
        assertEq(
            maxAmountToDepositMulti,
            IMetaVault(metaVaults[MULTI_VAULT_INDEX]).maxDeposit(address(this))[0],
            "max deposit for MultiVault wasn't change"
        );
        assertGt(wrappedBalanceAfter, wrappedBalanceBefore, "balance should increase after deposit");
        assertEq(
            wrappedMeta.maxDeposit(address(this)), type(uint).max, "MetaVault.maxDeposit should be still unlimited"
        );

        // ---- Withdraw back
        uint amountToWithdraw = wrappedMeta.maxWithdraw(address(this));
        uint shares = wrappedMeta.previewWithdraw(amountToWithdraw);

        vm.prank(address(this));
        wrappedMeta.withdraw(amountToWithdraw, address(this), address(this), shares * 101 / 100); // 1% slippage

        assertEq(wrappedMeta.balanceOf(address(this)), 0, "balance should be zero after withdraw");
        assertEq(metaVault.balanceOf(address(this)), balanceBefore, "get all meta vault tokens back after withdraw");
    }

    //endregion -------------------------------------------- Test Wrapped Meta Vault

    //region -------------------------------------------- Test Wrapped Multi Vault
    function testWrappedMultiVaultMaxDeposit() public view {
        IWrappedMetaVault wrappedMulti = IWrappedMetaVault(wrappedVaults[MULTI_VAULT_INDEX]);
        IMetaVault multiVault = IMetaVault(metaVaults[MULTI_VAULT_INDEX]);

        // max deposit amount to MultiVault
        uint maxAmountToDepositMulti = multiVault.maxDeposit(address(this))[0];

        // max deposit amount to wrapped
        uint maxAmountToDepositWrapped = wrappedMulti.maxDeposit(address(this));

        assertEq(maxAmountToDepositMulti, maxAmountToDepositWrapped, "multi.maxDeposit = wrapped.maxDeposit");
    }

    function testWrappedMultiVaultDepositMax() public {
        IWrappedMetaVault wrappedMulti = IWrappedMetaVault(wrappedVaults[MULTI_VAULT_INDEX]);

        // ---- Reduce available liquidity in Silo on 99% (to avoid price impact problems during swap of scUSD to USDC)
        _borrowAlmostAllCash(
            ISilo(SonicConstantsLib.SILO_VAULT_121_WMETAUSD), ISilo(SonicConstantsLib.SILO_VAULT_121_USDC), 99_00
        );
        _borrowAlmostAllCash(
            ISilo(SonicConstantsLib.SILO_VAULT_125_WMETAUSD), ISilo(SonicConstantsLib.SILO_VAULT_125_SCUSD), 99_00
        );

        uint maxAmountToDepositMulti = IMetaVault(metaVaults[MULTI_VAULT_INDEX]).maxDeposit(address(this))[0];

        // ------------------------------ Try to deposit max possible amount
        uint maxAmountToDeposit = wrappedMulti.maxDeposit(address(this)); // amount of metaUSD to deposit in MultiVault

        uint balanceBefore = wrappedMulti.balanceOf(address(this));
        (uint deposited, uint amountConsumedEmitted) = _tryToDeposit(wrappedMulti, maxAmountToDeposit, false);
        uint balanceAfter = wrappedMulti.balanceOf(address(this));

        (uint maxDepositAmount02, uint maxDepositAmount12) = _getMaxAmountsToDeposit();

        assertEq(maxAmountToDeposit, maxAmountToDepositMulti, "meta.maxDeposit should be equal to multi.maxDeposit");
        assertEq(deposited, maxAmountToDeposit, "Deposit max possible amount should be successful");
        assertLe(maxDepositAmount02 + maxDepositAmount12, 10e18, "Nothing to deposit anymore");
        assertEq(deposited, amountConsumedEmitted, "correct amount consumed is received");
        assertGt(balanceAfter, balanceBefore, "balance should increase after deposit");

        // ---- Withdraw back
        uint maxWithdraw = wrappedMulti.maxWithdraw(address(this));
        uint withdrawn = _tryToWithdraw(wrappedMulti, maxWithdraw);

        assertEq(wrappedMulti.balanceOf(address(this)), 0, "balance should be zero after withdraw");
        assertLt(
            _getDiffPercent18(withdrawn, deposited), 1e18 / 1000, "withdrawn amount should be equal to deposited amount"
        );
    }

    function testWrappedMultiVaultDepositTooMuch() public {
        IWrappedMetaVault wrappedMulti = IWrappedMetaVault(wrappedVaults[MULTI_VAULT_INDEX]);

        // ---- Reduce available liquidity in Silo on 99% (to avoid price impact problems during swap of scUSD to USDC)
        _borrowAlmostAllCash(
            ISilo(SonicConstantsLib.SILO_VAULT_121_WMETAUSD), ISilo(SonicConstantsLib.SILO_VAULT_121_USDC), 99_00
        );
        _borrowAlmostAllCash(
            ISilo(SonicConstantsLib.SILO_VAULT_125_WMETAUSD), ISilo(SonicConstantsLib.SILO_VAULT_125_SCUSD), 99_00
        );

        wrappedMulti.maxDeposit(address(this));

        // ------------------------------ Try to deposit more than maxDeposit (and get refund)
        uint amountToDepositTooMuch = wrappedMulti.maxDeposit(address(this)) * 110 / 100; // increase by 10%
        _tryToDeposit(wrappedMulti, amountToDepositTooMuch, true);
    }

    //endregion -------------------------------------------- Test Wrapped Multi Vault

    //region -------------------------------------------- Test MetaVault
    function testMetaVaultMaxDeposit() public view {
        IMetaVault multiVault = IMetaVault(metaVaults[MULTI_VAULT_INDEX]);
        IMetaVault metaVault = IMetaVault(metaVaults[META_VAULT_INDEX]);

        // max deposit amounts to sub-vault
        (uint maxDepositAmount0, uint maxDepositAmount1) = _getMaxAmountsToDeposit();

        // max deposit amount to MultiVault
        uint maxAmountToDepositMulti = multiVault.maxDeposit(address(this))[0];

        // max deposit amount to MetaVault
        uint maxAmountToDepositMeta = metaVault.maxDeposit(address(this))[0];

        assertEq(maxDepositAmount0 + maxDepositAmount1, maxAmountToDepositMulti, "sum of sub-vaults == multivault");
        assertEq(maxAmountToDepositMulti, maxAmountToDepositMeta, "multi == meta");
    }

    function testMetaVaultDepositMax() public {
        IMetaVault metaVault = IMetaVault(metaVaults[META_VAULT_INDEX]);

        // ---- Reduce available liquidity in Silo on 99% (to avoid price impact problems during swap of scUSD to USDC)
        _borrowAlmostAllCash(
            ISilo(SonicConstantsLib.SILO_VAULT_121_WMETAUSD), ISilo(SonicConstantsLib.SILO_VAULT_121_USDC), 99_00
        );
        _borrowAlmostAllCash(
            ISilo(SonicConstantsLib.SILO_VAULT_125_WMETAUSD), ISilo(SonicConstantsLib.SILO_VAULT_125_SCUSD), 99_00
        );

        uint maxAmountToDepositMulti = IMetaVault(metaVaults[MULTI_VAULT_INDEX]).maxDeposit(address(this))[0];

        // ------------------------------ Try to deposit max possible amount
        uint[] memory maxAmountToDeposit = metaVault.maxDeposit(address(this)); // amount of metaUSD to deposit in MultiVault

        uint balanceBefore = metaVault.balanceOf(address(this));
        (uint deposited, uint amountConsumedEmitted) = _tryToDeposit(metaVault, maxAmountToDeposit, false);
        uint balanceAfter = metaVault.balanceOf(address(this));

        (uint maxDepositAmount02, uint maxDepositAmount12) = _getMaxAmountsToDeposit();

        assertEq(maxAmountToDeposit[0], maxAmountToDepositMulti, "meta.maxDeposit should be equal to multi.maxDeposit");
        assertEq(deposited, maxAmountToDeposit[0], "Deposit max possible amount should be successful");
        assertLe(maxDepositAmount02 + maxDepositAmount12, 10e18, "Nothing to deposit anymore");
        assertEq(deposited, amountConsumedEmitted, "correct amount consumed is received");
        assertGt(balanceAfter, balanceBefore, "balance should increase after deposit");

        // ---- Withdraw back
        uint withdrawn = _tryToWithdraw(metaVault, balanceAfter - balanceBefore);
        assertLt(
            _getDiffPercent18(withdrawn, deposited), 1e18 / 1000, "withdrawn amount should be equal to deposited amount"
        );
    }

    function testMetaVaultDepositTooMuch() public {
        IMetaVault metaVault = IMetaVault(metaVaults[META_VAULT_INDEX]);

        // ---- Reduce available liquidity in Silo on 99% (to avoid price impact problems during swap of scUSD to USDC)
        _borrowAlmostAllCash(
            ISilo(SonicConstantsLib.SILO_VAULT_121_WMETAUSD), ISilo(SonicConstantsLib.SILO_VAULT_121_USDC), 99_00
        );
        _borrowAlmostAllCash(
            ISilo(SonicConstantsLib.SILO_VAULT_125_WMETAUSD), ISilo(SonicConstantsLib.SILO_VAULT_125_SCUSD), 99_00
        );

        uint maxAmountToDepositMulti = IMetaVault(metaVaults[MULTI_VAULT_INDEX]).maxDeposit(address(this))[0];

        // ------------------------------ Try to deposit more than maxDeposit (and get refund)
        uint[] memory amountToDepositTooMuch = metaVault.maxDeposit(address(this));
        amountToDepositTooMuch[0] = amountToDepositTooMuch[0] * 110 / 100; // increase by 10%

        uint balanceBefore = metaVault.balanceOf(address(this));
        (uint deposited,) = _tryToDeposit(metaVault, amountToDepositTooMuch, false);
        uint balanceAfter = metaVault.balanceOf(address(this));

        uint refund = amountToDepositTooMuch[0] - deposited;

        assertEq(deposited, maxAmountToDepositMulti, "Deposit max possible amount only");
        assertApproxEqAbs(refund, maxAmountToDepositMulti * 10 / 100, 1, "expected 10% refund");

        // ---- Withdraw back
        uint withdrawn = _tryToWithdraw(metaVault, balanceAfter - balanceBefore);
        assertLt(
            _getDiffPercent18(withdrawn, deposited), 1e18 / 1000, "withdrawn amount should be equal to deposited amount"
        );
    }

    //endregion -------------------------------------------- Test MetaVault

    //region -------------------------------------------- Test MultiVault
    function testDepositSmallAmount() public {
        uint smallAmountMetaUSD = 100e18;
        IMetaVault multiVault = IMetaVault(metaVaults[MULTI_VAULT_INDEX]);
        assertEq(multiVault.vaults().length, 2, "MultiVault should have 2 sub-vaults");

        // ---- Get max deposit amounts and detect target vault
        (uint maxDepositAmount0, uint maxDepositAmount1) = _getMaxAmountsToDeposit();
        uint targetVaultIndex = multiVault.vaultForDeposit() == multiVault.vaults()[0] ? 0 : 1;

        // ---- Deposit single decimal
        uint[] memory amountToDeposit = new uint[](1);
        amountToDeposit[0] = smallAmountMetaUSD;

        uint balanceBefore = multiVault.balanceOf(address(this));
        (uint deposited, uint amountConsumedEmitted) = _tryToDeposit(multiVault, amountToDeposit, false);
        uint balanceAfter = multiVault.balanceOf(address(this));

        (uint maxDepositAmount02, uint maxDepositAmount12) = _getMaxAmountsToDeposit();

        assertEq(deposited, smallAmountMetaUSD, "Deposit of small amount should be successful");
        assertGe(
            targetVaultIndex == 0 ? maxDepositAmount0 : maxDepositAmount1,
            targetVaultIndex == 0 ? maxDepositAmount02 : maxDepositAmount12,
            "deposit was made to the target vault"
        );
        assertEq(
            targetVaultIndex == 0 ? maxDepositAmount1 : maxDepositAmount0,
            targetVaultIndex == 0 ? maxDepositAmount12 : maxDepositAmount02,
            "second sub-vault should not be affected by deposit"
        );
        assertEq(amountConsumedEmitted, smallAmountMetaUSD, "correct amount consumed is received");
        assertGt(balanceAfter, balanceBefore, "balance should increase after deposit");

        // ---- Withdraw back
        uint withdrawn = _tryToWithdraw(multiVault, balanceAfter - balanceBefore);
        assertLt(
            _getDiffPercent18(withdrawn, deposited),
            1e18 / 1000,
            "withdrawn amount should be almost equal to deposited small amount"
        );
    }

    /// @notice Try to deposit exact maxDeposit amount
    function testMultiDepositMax() public {
        IMetaVault multiVault = IMetaVault(metaVaults[MULTI_VAULT_INDEX]);
        assertEq(multiVault.vaults().length, 2, "MultiVault should have 2 sub-vaults");

        // ---- Reduce available liquidity in Silo on 99% (to avoid price impact problems during swap of scUSD to USDC)
        _borrowAlmostAllCash(
            ISilo(SonicConstantsLib.SILO_VAULT_121_WMETAUSD), ISilo(SonicConstantsLib.SILO_VAULT_121_USDC), 99_00
        );
        _borrowAlmostAllCash(
            ISilo(SonicConstantsLib.SILO_VAULT_125_WMETAUSD), ISilo(SonicConstantsLib.SILO_VAULT_125_SCUSD), 99_00
        );

        (uint maxDepositAmount0, uint maxDepositAmount1) = _getMaxAmountsToDeposit();

        // ------------------------------ Try to deposit max possible amount
        uint[] memory maxAmountToDeposit = multiVault.maxDeposit(address(this)); // amount of metaUSD to deposit in MultiVault

        uint balanceBefore = multiVault.balanceOf(address(this));
        (uint deposited, uint amountConsumedEmitted) = _tryToDeposit(multiVault, maxAmountToDeposit, false);
        uint balanceAfter = multiVault.balanceOf(address(this));

        (uint maxDepositAmount02, uint maxDepositAmount12) = _getMaxAmountsToDeposit();

        assertEq(
            maxAmountToDeposit[0],
            maxDepositAmount0 + maxDepositAmount1,
            "maxDeposit should be equal to sum of max deposits of sub-vaults"
        );
        assertEq(deposited, maxAmountToDeposit[0], "Deposit max possible amount should be successful");
        assertLe(maxDepositAmount02 + maxDepositAmount12, 10e18, "Nothing to deposit anymore");
        assertEq(deposited, amountConsumedEmitted, "correct amount consumed is received");
        assertGt(balanceAfter, balanceBefore, "balance should increase after deposit");

        // ---- Withdraw back
        uint withdrawn = _tryToWithdraw(multiVault, balanceAfter - balanceBefore);
        assertLt(
            _getDiffPercent18(withdrawn, deposited), 1e18 / 1000, "withdrawn amount should be equal to deposited amount"
        );
    }

    /// @notice Try to deposit more than maxDeposit amount
    function testMultiDepositTooMuch() public {
        IMetaVault multiVault = IMetaVault(metaVaults[MULTI_VAULT_INDEX]);
        assertEq(multiVault.vaults().length, 2, "MultiVault should have 2 sub-vaults");

        // ---- Reduce available liquidity in Silo on 99% (to avoid price impact problems during swap of scUSD to USDC)
        _borrowAlmostAllCash(
            ISilo(SonicConstantsLib.SILO_VAULT_121_WMETAUSD), ISilo(SonicConstantsLib.SILO_VAULT_121_USDC), 99_00
        );
        _borrowAlmostAllCash(
            ISilo(SonicConstantsLib.SILO_VAULT_125_WMETAUSD), ISilo(SonicConstantsLib.SILO_VAULT_125_SCUSD), 99_00
        );

        // ------------------------------ Try to deposit more than maxDeposit (and get refund)
        uint[] memory maxAmountToDeposit = multiVault.maxDeposit(address(this)); // amount of metaUSD to deposit in MultiVault
        uint[] memory amountToDepositTooMuch = multiVault.maxDeposit(address(this));
        amountToDepositTooMuch[0] = amountToDepositTooMuch[0] * 110 / 100; // increase by 10%

        uint balanceBefore = multiVault.balanceOf(address(this));
        (uint deposited,) = _tryToDeposit(multiVault, amountToDepositTooMuch, false);
        uint balanceAfter = multiVault.balanceOf(address(this));

        uint refund = amountToDepositTooMuch[0] - deposited;

        assertEq(deposited, maxAmountToDeposit[0], "Deposit max possible amount only");
        assertApproxEqAbs(refund, maxAmountToDeposit[0] * 10 / 100, 1, "expected 10% refund");

        // ---- Withdraw back
        uint withdrawn = _tryToWithdraw(multiVault, balanceAfter - balanceBefore);
        assertLt(
            _getDiffPercent18(withdrawn, deposited), 1e18 / 1000, "withdrawn amount should be equal to deposited amount"
        );
    }

    /// @notice Try to deposit maxDepositAmount0 + dust, maxDepositAmount1 - dust
    function testMultiDepositWithPlusAddon() public {
        _testMultiDepositWithPlusAddon_Fuzzy(7518456257831769833, 99_98);
    }

    /// @notice Try to deposit maxDepositAmount0 - dust, maxDepositAmount1 + dust
    function testMultiDepositWithMinusAddon() public {
        _testMultiDepositWithMinusAddon_Fuzzy(7518456257831769833, 99_98);
    }

    function testMultiDepositWithMinusAddon2() public {
        _testMultiDepositWithMinusAddon_Fuzzy(9999000000008388607, 99_99);
    }

    function testMultiDepositProportion() public {
        _testMultiDepositProportion_Fuzzy(618033988768952984, 99_98); // 0.618e18
    }

    function testMultiDepositProportion2() public {
        _testMultiDepositProportion_Fuzzy(677546976265931812, 99_29);
    }

    //endregion -------------------------------------------- Test MultiVault

    //region -------------------------------------------- Long fuzzy tests (change internal to public to run)
    function testMultiDepositWithPlusAddon_Fuzzy(uint addon, uint borrowPercent) internal {
        addon = bound(addon, 1e15, 10e18); // 0.001 to 10
        borrowPercent = bound(borrowPercent, 99_90, 99_99);

        _testMultiDepositWithPlusAddon_Fuzzy(addon, borrowPercent);
    }

    function testMultiDepositWithMinusAddon_Fuzzy(uint addon, uint borrowPercent) internal {
        addon = bound(addon, 1e15, 10e18); // 0.001 to 10
        borrowPercent = bound(borrowPercent, 99_90, 99_99);

        _testMultiDepositWithMinusAddon_Fuzzy(addon, borrowPercent);
    }

    function testMultiDepositWithProportion_Fuzzy(uint proportion18n, uint borrowPercent) internal {
        proportion18n = bound(proportion18n, 1e17, 1e18); // 0.001 to 10
        borrowPercent = bound(borrowPercent, 99_00, 99_99);

        _testMultiDepositProportion_Fuzzy(proportion18n, borrowPercent);
    }

    //endregion -------------------------------------------- Long fuzzy tests (change internal to public to run)

    //region -------------------------------------------- Test implementation
    /// @notice Try to deposit maxDepositAmount0 + dust, maxDepositAmount1 - dust
    function _testMultiDepositWithPlusAddon_Fuzzy(uint addon, uint borrowPercent) internal {
        IMetaVault multiVault = IMetaVault(metaVaults[MULTI_VAULT_INDEX]);

        // ---- Reduce available liquidity in Silo on 99% (to avoid price impact problems during swap of scUSD to USDC)
        _borrowAlmostAllCash(
            ISilo(SonicConstantsLib.SILO_VAULT_125_WMETAUSD),
            ISilo(SonicConstantsLib.SILO_VAULT_125_SCUSD),
            borrowPercent
        );
        _borrowAlmostAllCash(
            ISilo(SonicConstantsLib.SILO_VAULT_121_WMETAUSD),
            ISilo(SonicConstantsLib.SILO_VAULT_121_USDC),
            borrowPercent
        );

        // ---- Get max deposit amounts
        (uint maxDepositAmount0, uint maxDepositAmount1) = _getMaxAmountsToDeposit();
        uint[] memory amountToDeposit = multiVault.maxDeposit(address(this));

        // ---- Make two deposits
        uint balanceBefore = multiVault.balanceOf(address(this));

        amountToDeposit[0] = maxDepositAmount0 - addon;
        (uint deposited,) = _tryToDeposit(multiVault, amountToDeposit, false);

        amountToDeposit[0] = maxDepositAmount1 + addon;
        (uint deposited1,) = _tryToDeposit(multiVault, amountToDeposit, false);

        uint balanceAfter = multiVault.balanceOf(address(this));

        // ---- Check results
        (uint maxDepositAmount02, uint maxDepositAmount12) = _getMaxAmountsToDeposit();

        assertEq(
            deposited + deposited1,
            maxDepositAmount0 + maxDepositAmount1,
            "Deposit maxDepositAmount0 - dust, maxDepositAmount1 + dust should be successful"
        );
        assertLt(maxDepositAmount02 + maxDepositAmount12, 1e18, "nothing to deposit anymore");

        // ---- Withdraw back
        uint withdrawn = _tryToWithdraw(multiVault, balanceAfter - balanceBefore);
        assertLt(
            _getDiffPercent18(withdrawn, deposited + deposited1),
            1e18 / 1000,
            "withdrawn amount should be equal to deposited amount"
        );
    }

    /// @notice Try to deposit maxDepositAmount0 - dust, maxDepositAmount1 + dust
    function _testMultiDepositWithMinusAddon_Fuzzy(uint addon, uint borrowPercent) internal {
        IMetaVault multiVault = IMetaVault(metaVaults[MULTI_VAULT_INDEX]);

        // ---- Reduce available liquidity in Silo on 99% (to avoid price impact problems during swap of scUSD to USDC)
        _borrowAlmostAllCash(
            ISilo(SonicConstantsLib.SILO_VAULT_125_WMETAUSD),
            ISilo(SonicConstantsLib.SILO_VAULT_125_SCUSD),
            borrowPercent
        );
        _borrowAlmostAllCash(
            ISilo(SonicConstantsLib.SILO_VAULT_121_WMETAUSD),
            ISilo(SonicConstantsLib.SILO_VAULT_121_USDC),
            borrowPercent
        );

        // ---- Get max deposit amounts
        (uint maxDepositAmount0, uint maxDepositAmount1) = _getMaxAmountsToDeposit();
        uint[] memory amountToDeposit = multiVault.maxDeposit(address(this));

        // ---- Make two deposits
        uint balanceBefore = multiVault.balanceOf(address(this));

        amountToDeposit[0] = maxDepositAmount0 + addon;
        (uint deposited,) = _tryToDeposit(multiVault, amountToDeposit, false);

        amountToDeposit[0] = maxDepositAmount1 > addon ? maxDepositAmount1 - addon : 0;
        (uint deposited1,) = amountToDeposit[0] == 0 ? (0, 0) : _tryToDeposit(multiVault, amountToDeposit, false);

        uint balanceAfter = multiVault.balanceOf(address(this));
        // ---- Check results
        (uint maxDepositAmount02, uint maxDepositAmount12) = _getMaxAmountsToDeposit();

        assertEq(
            deposited + deposited1,
            maxDepositAmount0 + maxDepositAmount1,
            "Deposit maxDepositAmount0 - dust, maxDepositAmount1 + dust should be successful"
        );
        assertLt(maxDepositAmount02 + maxDepositAmount12, 10e18, "Almost nothing to deposit anymore");

        // ---- Withdraw back
        uint withdrawn = _tryToWithdraw(multiVault, balanceAfter - balanceBefore);
        assertLt(
            _getDiffPercent18(withdrawn, deposited + deposited1),
            1e18 / 1000,
            "withdrawn amount should be equal to deposited amount"
        );
    }

    function _testMultiDepositProportion_Fuzzy(uint proportion18, uint borrowPercent) internal {
        IMetaVault multiVault = IMetaVault(metaVaults[MULTI_VAULT_INDEX]);

        // ---- Reduce available liquidity in Silo on 99% (to avoid price impact problems during swap of scUSD to USDC)
        _borrowAlmostAllCash(
            ISilo(SonicConstantsLib.SILO_VAULT_125_WMETAUSD),
            ISilo(SonicConstantsLib.SILO_VAULT_125_SCUSD),
            borrowPercent
        );
        _borrowAlmostAllCash(
            ISilo(SonicConstantsLib.SILO_VAULT_121_WMETAUSD),
            ISilo(SonicConstantsLib.SILO_VAULT_121_USDC),
            borrowPercent
        );

        // ---- Get max deposit amounts
        (uint maxDepositAmount0, uint maxDepositAmount1) = _getMaxAmountsToDeposit();
        uint[] memory amountToDeposit = multiVault.maxDeposit(address(this));
        uint part1 = (maxDepositAmount0 + maxDepositAmount1) * proportion18 / 1e18;
        uint part2 = amountToDeposit[0] - part1;

        // ---- Make two deposits
        uint balanceBefore = multiVault.balanceOf(address(this));

        amountToDeposit[0] = part1;
        (uint deposited,) = _tryToDeposit(multiVault, amountToDeposit, false);

        amountToDeposit[0] = part2;
        (uint deposited1,) = _tryToDeposit(multiVault, amountToDeposit, false);

        uint balanceAfter = multiVault.balanceOf(address(this));

        // ---- Check results
        (uint maxDepositAmount02, uint maxDepositAmount12) = _getMaxAmountsToDeposit();

        assertEq(
            deposited + deposited1,
            maxDepositAmount0 + maxDepositAmount1,
            "Deposit maxDepositAmount0 - dust, maxDepositAmount1 + dust should be successful"
        );
        assertLt(maxDepositAmount02 + maxDepositAmount12, 10e18, "nothing to deposit anymore");

        // ---- Withdraw back
        uint withdrawn = _tryToWithdraw(multiVault, balanceAfter - balanceBefore);
        assertLt(
            _getDiffPercent18(withdrawn, deposited + deposited1),
            1e18 / 1000,
            "withdrawn amount should be equal to deposited amount"
        );
    }

    //endregion -------------------------------------------- Test implementation

    //region -------------------------------------------- Internal functions
    function _initialDeposit() internal {
        uint[] memory amountToDeposit = new uint[](1);
        amountToDeposit[0] = 222333e16;
        _tryToDeposit(IMetaVault(metaVaults[META_VAULT_INDEX]), amountToDeposit, false); // first sub-vault
        _tryToDeposit(IMetaVault(metaVaults[META_VAULT_INDEX]), amountToDeposit, false); // second sub-vault
    }

    function _tryToWithdraw(IMetaVault multiVault, uint amountToWithdraw) internal returns (uint withdrawn) {
        IWrappedMetaVault wrapped = IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);
        uint balanceBefore = wrapped.balanceOf(address(this));

        vm.prank(address(this));
        wrapped.approve(address(multiVault), amountToWithdraw);

        vm.prank(address(this));
        multiVault.withdrawAssets(multiVault.assetsForWithdraw(), amountToWithdraw, new uint[](1));
        vm.roll(block.number + 6);

        return wrapped.balanceOf(address(this)) - balanceBefore;
    }

    function _tryToWithdraw(IWrappedMetaVault targetWrapped, uint amountToWithdraw) internal returns (uint withdrawn) {
        IWrappedMetaVault wrapped = IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);
        uint balanceBefore = wrapped.balanceOf(address(this));

        vm.prank(address(this));
        wrapped.approve(address(targetWrapped), amountToWithdraw);

        uint shares = targetWrapped.previewWithdraw(amountToWithdraw);

        vm.prank(address(this));
        targetWrapped.withdraw(amountToWithdraw, address(this), address(this), shares * 101 / 100); // 1% slippage
        vm.roll(block.number + 6);

        return wrapped.balanceOf(address(this)) - balanceBefore;
    }

    function _getEmittedConsumedAmount() internal view returns (uint amountConsumedEmitted) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSig = keccak256("DepositAssets(address,address[],uint256[],uint256)");

        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSig) {
                address receiver = address(uint160(uint(logs[i].topics[1])));
                if (receiver == address(this)) {
                    (, uint[] memory amountsConsumed,) = abi.decode(logs[i].data, (address[], uint[], uint));
                    return amountsConsumed[0];
                }
            }
        }

        return 0;
    }

    function _getDepositAmountToWrapped() internal view returns (uint amountConsumedEmitted) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSig = keccak256("Deposit(address,address,uint256,uint256)");

        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSig) {
                address receiver = address(uint160(uint(logs[i].topics[2])));
                if (receiver == address(this)) {
                    (amountConsumedEmitted,) = abi.decode(logs[i].data, (uint, uint));
                    return amountConsumedEmitted;
                }
            }
        }

        return 0;
    }

    function _getMaxAmountsToDeposit() internal view returns (uint maxDepositAmount0, uint maxDepositAmount1) {
        IMetaVault multiVault = IMetaVault(metaVaults[MULTI_VAULT_INDEX]);
        maxDepositAmount0 = IStabilityVault(multiVault.vaults()[0]).maxDeposit(address(this))[0];
        maxDepositAmount1 = IStabilityVault(multiVault.vaults()[1]).maxDeposit(address(this))[0];
    }

    /// @return deposited amount of metaUSD deposited to MultiVault
    function _tryToDeposit(
        IMetaVault multiVault,
        uint[] memory maxAmounts,
        bool shouldRevert
    ) internal returns (uint deposited, uint amountConsumedEmitted) {
        IMetaVault wrapped = IMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);
        _getMetaUsdOnBalance(address(this), maxAmounts[0], true);

        vm.prank(address(this));
        wrapped.approve(address(multiVault), maxAmounts[0]);

        address[] memory assetsForDeposit = multiVault.assetsForDeposit();
        uint balanceMetaUsdBefore = wrapped.balanceOf(address(this));

        vm.recordLogs();

        if (shouldRevert) {
            vm.expectRevert();
        }
        vm.prank(address(this));
        multiVault.depositAssets(assetsForDeposit, maxAmounts, 0, address(this));
        amountConsumedEmitted = _getEmittedConsumedAmount();
        vm.roll(block.number + 6);

        deposited = balanceMetaUsdBefore - wrapped.balanceOf(address(this));

        assertEq(deposited, amountConsumedEmitted, "amountConsumedEmitted should be equal to deposited amount");
        for (uint i = 0; i < multiVault.vaults().length; ++i) {
            assertEq(
                wrapped.allowance(address(multiVault), multiVault.vaults()[i]),
                0,
                "metaUSD allowance 0 should be reset after deposit"
            );
        }

        return (deposited, amountConsumedEmitted);
    }

    function _tryToDeposit(
        IWrappedMetaVault targetWrappedMetaVault,
        uint amountToDeposit,
        bool shouldRevert
    ) internal returns (uint deposited, uint amountConsumedEmitted) {
        IMetaVault wrapped = IMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);
        _getMetaUsdOnBalance(address(this), amountToDeposit, true);

        vm.prank(address(this));
        wrapped.approve(address(targetWrappedMetaVault), amountToDeposit);

        uint balanceMetaUsdBefore = wrapped.balanceOf(address(this));

        vm.recordLogs();

        vm.prank(address(this));
        // targetWrappedMetaVault.deposit(amountToDeposit, address(this), 0);
        try targetWrappedMetaVault.deposit(amountToDeposit, address(this), 0) {
            require(!shouldRevert, "Error ERC4626ExceededMaxDeposit wasn't thrown");
        } catch (bytes memory reason) {
            require(
                reason.length >= 4 && bytes4(reason) == ERC4626Upgradeable.ERC4626ExceededMaxDeposit.selector,
                "Some other error was thrown instead of ERC4626ExceededMaxDeposit"
            );
        }

        amountConsumedEmitted = _getDepositAmountToWrapped();
        vm.roll(block.number + 6);

        deposited = balanceMetaUsdBefore - wrapped.balanceOf(address(this));

        assertEq(deposited, amountConsumedEmitted, "amountConsumedEmitted should be equal to deposited amount");
        return (deposited, amountConsumedEmitted);
    }

    function _getMetaUsdOnBalance(address user, uint amountMetaVaultTokens, bool wrap) internal {
        IMetaVault metaVault = IMetaVault(SonicConstantsLib.METAVAULT_METAUSD);

        // we don't know exact amount of USDC required to receive exact amountMetaVaultTokens
        // so we deposit a bit large amount of USDC
        address[] memory _assets = metaVault.assetsForDeposit();
        uint[] memory amountsMax = new uint[](1);
        amountsMax[0] = 2 * amountMetaVaultTokens / 1e12;

        deal(SonicConstantsLib.TOKEN_USDC, user, amountsMax[0]);

        vm.startPrank(user);
        IERC20(SonicConstantsLib.TOKEN_USDC)
            .approve(address(metaVault), IERC20(SonicConstantsLib.TOKEN_USDC).balanceOf(user));
        metaVault.depositAssets(_assets, amountsMax, 0, user);
        vm.roll(block.number + 6);
        vm.stopPrank();

        if (wrap) {
            vm.startPrank(user);
            IWrappedMetaVault wrappedMetaVault = IWrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);
            metaVault.approve(address(wrappedMetaVault), metaVault.balanceOf(user));
            wrappedMetaVault.deposit(metaVault.balanceOf(user), user, 0);
            vm.stopPrank();

            vm.roll(block.number + 6);
        }
    }

    function _borrowAlmostAllCash(ISilo collateralVault, ISilo debtVault, uint borrowPercent100_00) internal {
        address user = address(214385);
        uint maxLiquidityToBorrow = debtVault.getLiquidity();
        uint collateralApproxAmount = 10 * maxLiquidityToBorrow * 1e12;

        // use deal to avoid increasing liquidity in the silo pool
        deal(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, user, collateralApproxAmount);
        // _getMetaUsdOnBalance(user, collateralApproxAmount, true);

        uint balance = IERC20(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD).balanceOf(user);

        vm.prank(user);
        IERC20(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD).approve(address(collateralVault), balance);

        vm.prank(user);
        collateralVault.deposit(balance, user);

        vm.prank(user);
        debtVault.borrow(
            maxLiquidityToBorrow * borrowPercent100_00 / 100_00, // borrow i.e. 99% of available liquidity
            user,
            user
        );

        uint maxLiquidityToBorrow2 = debtVault.getLiquidity();
        assertLt(maxLiquidityToBorrow2, maxLiquidityToBorrow, "Liquidity should be reduced after borrow");
    }

    function _setUpFlashLoanVault(uint additionalAmount) internal {
        IMetaVault multiVault = IMetaVault(metaVaults[MULTI_VAULT_INDEX]);
        address vault0 = multiVault.vaults()[0];
        address vault1 = multiVault.vaults()[1];

        // Set up flash loan vault for the strategy
        _setFlashLoanVault(
            ILeverageLendingStrategy(address(IVault(vault0).strategy())),
            SonicConstantsLib.BEETS_VAULT_V3,
            SonicConstantsLib.BEETS_VAULT_V3,
            uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1)
        );

        _setFlashLoanVault(
            ILeverageLendingStrategy(address(IVault(vault1).strategy())),
            SonicConstantsLib.BEETS_VAULT_V3,
            SonicConstantsLib.BEETS_VAULT_V3,
            uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1)
        );

        if (additionalAmount != 0) {
            // Add additional amount to the flash loan vault to avoid insufficient balance
            deal(SonicConstantsLib.TOKEN_USDC, SonicConstantsLib.BEETS_VAULT_V3, additionalAmount);
            deal(SonicConstantsLib.TOKEN_SCUSD, SonicConstantsLib.BEETS_VAULT_V3, additionalAmount);
        }
    }

    function _setFlashLoanVault(ILeverageLendingStrategy strategy, address vaultC, address vaultB, uint kind) internal {
        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();
        params[10] = kind;
        addresses[0] = vaultC;
        addresses[1] = vaultB;

        vm.prank(multisig);
        strategy.setUniversalParams(params, addresses);
    }

    //endregion -------------------------------------------- Internal functions

    //region -------------------------------------------- Helper functions
    function _setupMetaVaultFactory() internal {
        vm.prank(multisig);
        Platform(PLATFORM).setupMetaVaultFactory(address(metaVaultFactory));
    }

    function _setupImplementations() internal {
        address metaVaultImplementation = address(new MetaVault());
        address wrappedMetaVaultImplementation = address(new WrappedMetaVault());
        vm.prank(multisig);
        metaVaultFactory.setMetaVaultImplementation(metaVaultImplementation);
        vm.prank(multisig);
        metaVaultFactory.setWrappedMetaVaultImplementation(wrappedMetaVaultImplementation);
    }

    function _deployMetaVaultByMetaVaultFactory(
        string memory type_,
        address pegAsset,
        string memory name_,
        string memory symbol_,
        address[] memory vaults_,
        uint[] memory proportions_
    ) internal returns (address metaVaultProxy) {
        vm.prank(multisig);
        return metaVaultFactory.deployMetaVault(
            bytes32(abi.encodePacked(name_)), type_, pegAsset, name_, symbol_, vaults_, proportions_
        );
    }

    function _deployWrapper(address metaVault) internal returns (address wrapper) {
        vm.prank(multisig);
        return metaVaultFactory.deployWrapper(bytes32(uint(uint160(metaVault))), metaVault);
    }

    function _createVaultsAndStrategies(Factory factory) internal returns (address[] memory vaults) {
        uint farmId = factory.farmsLength() - 2;
        Strategy[] memory strategies = new Strategy[](2);
        strategies[0] = Strategy({
            id: StrategyIdLib.SILO_ALMF_FARM,
            pool: address(0),
            farmId: farmId,
            strategyInitAddresses: new address[](0),
            strategyInitNums: new uint[](0)
        });
        strategies[1] = Strategy({
            id: StrategyIdLib.SILO_ALMF_FARM,
            pool: address(0),
            farmId: farmId + 1,
            strategyInitAddresses: new address[](0),
            strategyInitNums: new uint[](0)
        });

        vaults = new address[](strategies.length);
        for (uint i; i < strategies.length; ++i) {
            IFactory.StrategyLogicConfig memory strategyConfig =
                factory.strategyLogicConfig(keccak256(bytes(strategies[i].id)));
            assertNotEq(
                strategyConfig.implementation, address(0), "Strategy implementation not found: put it to chain lib."
            );

            string[] memory types = IStrategy(strategyConfig.implementation).supportedVaultTypes();
            assertEq(types.length, 1, "Assume that the strategy supports only one vault type");

            address[] memory vaultInitAddresses = new address[](0);
            uint[] memory vaultInitNums = new uint[](0);
            address[] memory initStrategyAddresses;
            uint[] memory nums;
            int24[] memory ticks = new int24[](0);

            // farming
            nums = new uint[](1);
            nums[0] = strategies[i].farmId;

            factory.deployVaultAndStrategy(
                types[0], strategies[i].id, vaultInitAddresses, vaultInitNums, initStrategyAddresses, nums, ticks
            );

            vaults[i] = factory.deployedVault(factory.deployedVaultsLength() - 1);
        }
    }

    function _farms() internal pure returns (IFactory.Farm[] memory destFarms) {
        destFarms = new IFactory.Farm[](2);

        destFarms[0] = SonicFarmMakerLib._makeSiloALMFarm(
            SonicConstantsLib.SILO_VAULT_121_WMETAUSD,
            SonicConstantsLib.SILO_VAULT_121_USDC,
            SonicConstantsLib.BEETS_VAULT, // todo
            SonicConstantsLib.SILO_LENS // todo
        );

        destFarms[1] = SonicFarmMakerLib._makeSiloALMFarm(
            SonicConstantsLib.SILO_VAULT_125_WMETAUSD,
            SonicConstantsLib.SILO_VAULT_125_SCUSD,
            SonicConstantsLib.BEETS_VAULT, // todo
            SonicConstantsLib.SILO_LENS // todo
        );
    }

    function _updateCVaultImplementation(IFactory factory) internal {
        address vaultImplementation = address(new CVault());
        vm.prank(multisig);
        factory.setVaultImplementation(VaultTypeLib.COMPOUNDING, vaultImplementation);
    }

    function _upgradeMetaVault(address metaVault_) internal {
        // Upgrade MetaVault to the new implementation
        address vaultImplementation = address(new MetaVault());
        vm.prank(multisig);
        metaVaultFactory.setMetaVaultImplementation(vaultImplementation);
        address[] memory metaProxies = new address[](1);
        metaProxies[0] = address(metaVault_);
        vm.prank(multisig);
        metaVaultFactory.upgradeMetaProxies(metaProxies);
    }

    function _addAdapter() internal returns (address adapter) {
        Proxy proxy = new Proxy();
        proxy.initProxy(address(new MetaVaultAdapter()));
        MetaVaultAdapter(address(proxy)).init(PLATFORM);

        vm.prank(multisig);
        IPlatform(PLATFORM).addAmmAdapter(AmmAdapterIdLib.META_VAULT, address(proxy));

        return address(proxy);
    }

    function _routes() internal pure returns (ISwapper.AddPoolData[] memory pools) {
        pools = new ISwapper.AddPoolData[](2);
        uint i;
        pools[i++] = _makePoolData(
            SonicConstantsLib.METAVAULT_METAUSD,
            AmmAdapterIdLib.META_VAULT,
            SonicConstantsLib.METAVAULT_METAUSD,
            SonicConstantsLib.METAVAULT_METAUSD
        );
        pools[i++] = _makePoolData(
            SonicConstantsLib.WRAPPED_METAVAULT_METAUSD,
            AmmAdapterIdLib.ERC_4626,
            SonicConstantsLib.WRAPPED_METAVAULT_METAUSD,
            SonicConstantsLib.METAVAULT_METAUSD
        );
    }

    function _makePoolData(
        address pool,
        string memory ammAdapterId,
        address tokenIn,
        address tokenOut
    ) internal pure returns (ISwapper.AddPoolData memory) {
        return ISwapper.AddPoolData({pool: pool, ammAdapterId: ammAdapterId, tokenIn: tokenIn, tokenOut: tokenOut});
    }

    function _upgradePlatform() internal {
        address[] memory proxies = new address[](3);
        proxies[0] = address(IPlatform(PLATFORM).swapper());
        proxies[1] = address(IPlatform(PLATFORM).priceReader());
        proxies[2] = address(IPlatform(PLATFORM).factory());

        address[] memory implementations = new address[](3);
        implementations[0] = address(new Swapper());
        implementations[1] = address(new PriceReader());
        implementations[2] = address(new Factory());

        vm.prank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.03.1-alpha", proxies, implementations);

        skip(1 days);

        vm.prank(multisig);
        IPlatform(PLATFORM).upgrade();
    }

    function _getDiffPercent18(uint x, uint y) internal pure returns (uint) {
        return x > y ? (x - y) * 1e18 / x : (y - x) * 1e18 / x;
    }
    //endregion -------------------------------------------- Helper functions
}
