// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {RecoveryToken} from "../../src/core/vaults/RecoveryToken.sol";
import {WrappedMetaVault} from "../../src/core/vaults/WrappedMetaVault.sol";
import {MetaVaultFactory} from "../../src/core/MetaVaultFactory.sol";
import {AaveMerklFarmStrategy} from "../../src/strategies/AaveMerklFarmStrategy.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {IAToken} from "../../src/integrations/aave/IAToken.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IRecoveryToken} from "../../src/interfaces/IRecoveryToken.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IWrappedMetaVault} from "../../src/interfaces/IWrappedMetaVault.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {SiloStrategy} from "../../src/strategies/SiloStrategy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {console, Test} from "forge-std/Test.sol";
import {Factory} from "../../src/core/Factory.sol";
import {IProxy} from "../../src/interfaces/IProxy.sol";

/// #360 - withdraw underlying from MetaVaults
contract MetaVault360WithdrawUnderlyingSonicUpgrade is Test {
    // uint public constant FORK_BLOCK = 40824190; // Jul-30-2025 02:39:35 AM +UTC (before the hack of 04 aug 2025)
    // uint public constant FORK_BLOCK = 41962444; // Aug-07-2025 05:43:49 AM +UTC
    uint public constant FORK_BLOCK = 42104063; // Aug-08-2025 06:16:39 AM +UTC

    /// @notice Some user that has shares of MetaUSDC, not meta vault
    address public constant HOLDER_META_USDC = 0xEEEEEEE6d95E55A468D32FeB5d6648754d10A967;

    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public multisig;
    IMetaVault public metaVault;
    IMetaVaultFactory public metaVaultFactory;

    address internal user;
    address internal user2;

    address[15] internal LARGEST_META_USD_HOLDERS;

    address[12] internal LARGEST_WRAPPED_META_USD_HOLDERS;

    struct WrappedState {
        uint totalShares;
        uint totalSupply;
        uint totalAssets;
        uint totalAmountsOut;
        uint wrappedPrice;
        uint totalSupplyRecoveryToken;
        uint strategyBalanceUnderlying;
        uint wrappedBalanceUnderlying;
        uint[] userBalanceUnderlying;
        uint[] userBalancesWrapped;
        uint[] userBalanceRecoveryToken;
    }

    struct State {
        uint totalSupply;
        uint price;
        uint internalSharePrice;
        uint strategyBalanceUnderlying;
        uint userBalanceUnderlying;
        uint userBalanceMetaVaultTokens;
        uint userBalanceRecoveryToken;
        uint maxWithdrawUnderlying;
        uint wrappedPrice;
    }

    struct MultiState {
        uint totalSupply;
        uint price;
        uint internalSharePrice;
        uint strategyBalanceUnderlying;
        uint wrappedPrice;
        uint[] userBalanceUnderlying;
        uint[] userBalanceMetaVaultTokens;
        uint[] userBalanceRecoveryToken;
        uint[] maxWithdrawUnderlying;
        uint userBalanceUnderlyingTotal;
        uint userBalanceMetaVaultTokensTotal;
        uint userBalanceRecoveryTokenTotal;
        uint maxWithdrawUnderlyingTotal;
        uint metaVaultBalanceUnderlying;
    }

    struct ArraysForMetaVault {
        address[] owners;
        uint[] amounts;
        uint[] expectedUnderlying;
        uint[] minAmountsOut;
        bool[] paused;
    }

    struct ArraysForWrapped {
        address[] owners;
        uint[] shares;
        uint[] expectedUnderlying;
        uint[] minAmountsOut;
        bool[] paused;
    }

    constructor() {
        user = makeAddr("user");
        user2 = makeAddr("user2");

        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        multisig = IPlatform(PLATFORM).multisig();
        metaVaultFactory = IMetaVaultFactory(SonicConstantsLib.METAVAULT_FACTORY);
        metaVault = IMetaVault(SonicConstantsLib.METAVAULT_METAUSD);

        _upgradeMetaVault(address(metaVault));

        // all holders with balances > 1000 metaUSD except wrapped metaUSD
        LARGEST_META_USD_HOLDERS = [
            0x8901D9cf0272A2876525ee25Fcbb9E423c4B95f6,
            0x97006dB48f27A1312BbeD5E96dE146A97A78E396,
            0x59603A3AB3e33F07A2B9a4419399d502a1Fb6a95,
            0xc2d5904602e2d76D3D04EC28A5A1c52E136C4475,
            0xCE785cccAa0c163E6f83b381eBD608F98f694C44,
            0xf29593aC58C78ECC0bF1d0e8B55E819c5B521aE4,
            0x34F6eA796d06870db4dD5775D9e665539Bc6bBA0,
            0xa9714f7291251Bc1b0D0dBA6481959Ef814E171a,
            0xd63295C755F84FCd57663Ea2e2f9E6fee1830139,
            0x8C9C2f167792254C651FcA36CA40Ed9a229e5921,
            0xaC207c599e4A07F9A8cc5E9cf49B02E20AB7ba69,
            0x288a2395f027F65684D836754bA43Afa20CA09e6,
            0x5027457c50A3b45772baFE70e2E6f05D98514ad4,
            0xec8e3A07d6c5c172e821588EF1749b739A06b20E,
            0xdF5e92e18c282B61b509Fb3223BaC6c4d0C8dEE6
        ];

        LARGEST_WRAPPED_META_USD_HOLDERS = [
            0x6e8C150224D6e9B646889b96EFF6f7FD742e2C22,
            0xCCdDbBbd1E36a6EDA3a84CdCee2040A86225Ba71,
            0x287939376DCc571b5ee699DD8E72199989424A2E,
            0x06C319099BaC1a2b2797c55eF06667B4Ce62D226,
            0x6F11663766bB213003cD74EB09ff4c67145023c5,
            0xf29593aC58C78ECC0bF1d0e8B55E819c5B521aE4,
            0x859C08DDB344FaCf01027FE7e75C5DFA6230c7dE,
            0x60e2A70a4Ba833Fe94AF82f01742e7bfd8e18FA0,
            0x3e796a8eed2d57b334796F8356D882827770d7Fd,
            0x1D801dC616C79c499C5d38c998Ef2D0D6Cf868e8,
            0x2C00637a8CF228B8e882aB0BDfCDA22c159E1E6C,
            0x8f80791DcdAeb64794F53d4ab1c27BF4c21A4F41
        ];

        _upgradePlatform();
        _setupMetaVaultFactory();
        _upgradeFactory(); // upgrade to Factory v2.0.0
    }

    //region --------------------------------------- Tests for MetaUSDC/MetaScUSD (sub-meta-vaults)
    /// @dev MetaUSDC.withdrawUnderlying => cVault
    function testDepositWithdrawUnderlyingFromChildMetaVaultAMF() public {
        vm.prank(multisig);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);

        (IMetaVault subMetaVault, IStabilityVault vault) =
            _prepareSubVaultToDeposit(SonicConstantsLib.METAVAULT_METAUSDC, SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA0);
        _upgradeAmfStrategy(address(IVault(SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA0).strategy()));
        _upgradeCVault(SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA0);

        // ----------------------------------- detect underlying and amount to withdraw
        IStrategy strategy = IVault(address(vault)).strategy();

        vm.prank(multisig);
        AaveMerklFarmStrategy(address(strategy)).setUnderlying();

        assertNotEq(strategy.underlying(), address(0), "AMF: Underlying should not be zero address 2");

        // ----------------------------------- deposit assets into the given vault
        address[] memory assets = subMetaVault.assetsForDeposit();
        uint[] memory amounts = new uint[](1);
        amounts[0] = 1000e6;

        uint underlyingStrategyBalanceBeforeDeposit = IERC20(strategy.underlying()).balanceOf(address(strategy));

        deal(assets[0], user, amounts[0]);

        vm.prank(user);
        IERC20(assets[0]).approve(address(subMetaVault), amounts[0]);

        vm.prank(user);
        subMetaVault.depositAssets(assets, amounts, 0, user);

        uint underlyingStrategyBalanceAfterDeposit = IERC20(strategy.underlying()).balanceOf(address(strategy));

        // ----------------------------------- withdraw all underlying
        assets = new address[](1);
        assets[0] = strategy.underlying();

        uint amountToWithdraw = subMetaVault.maxWithdrawUnderlying(address(vault), user);
        uint expectedUnderlying = _getExpectedUnderlying(strategy, subMetaVault, amountToWithdraw);
        uint balanceUnderlyingBefore = IERC20(assets[0]).balanceOf(user);

        vm.prank(user);
        MetaVault(address(subMetaVault)).withdrawUnderlying(address(vault), amountToWithdraw, 0, user, user);
        // console.log("amountToWithdraw", amountToWithdraw);

        uint balanceUnderlyingAfter = IERC20(assets[0]).balanceOf(user);

        // ----------------------------------- check results
        assertApproxEqAbs(
            balanceUnderlyingAfter - balanceUnderlyingBefore,
            expectedUnderlying,
            1,
            "AMF: Withdrawn amount should match expected value 2"
        );

        assertEq(
            balanceUnderlyingAfter - balanceUnderlyingBefore,
            underlyingStrategyBalanceAfterDeposit - underlyingStrategyBalanceBeforeDeposit,
            "User has withdrawn all deposited underlying 2"
        );

        assertEq(
            balanceUnderlyingAfter - balanceUnderlyingBefore,
            1000e6,
            "User has withdrawn amount of atokens same to the deposited amount 2"
        );

        assertApproxEqAbs(subMetaVault.balanceOf(user), 0, 1e6, "User should have no shares left after withdraw 2");
    }

    /// @dev MetaUSDC.withdrawUnderlying => cVault
    function testWithdrawUnderlyingMetaUsdcAMF() public {
        // ----------------------------------- upgrade vaults and strategies
        vm.prank(multisig);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);

        IMetaVault subMetaVault = IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);
        IStabilityVault vault = IStabilityVault(SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA0);

        _upgradeAmfStrategy(address(IVault(SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA0).strategy()));
        _upgradeCVault(SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA0);

        // ----------------------------------- set up recovery tokens
        address recoveryToken = _createRecoveryToken(address(subMetaVault), bytes32(uint(0x500)));
        vm.prank(multisig);
        subMetaVault.setRecoveryToken(address(vault), recoveryToken);

        // ----------------------------------- detect underlying and amount to withdraw
        IStrategy strategy = IVault(address(vault)).strategy();

        vm.prank(multisig);
        AaveMerklFarmStrategy(address(strategy)).setUnderlying();

        assertNotEq(strategy.underlying(), address(0), "AMF: Underlying should not be zero address 12");

        // ----------------------------------- withdraw all underlying
        address[] memory assets = new address[](1);
        assets[0] = strategy.underlying();

        address holder = HOLDER_META_USDC;

        State memory stateBefore =
            _getMetaVaultState(subMetaVault, strategy, holder, SonicConstantsLib.WRAPPED_METAVAULT_METAUSDC);
        uint expectedUnderlying = _getExpectedUnderlying(strategy, subMetaVault, stateBefore.maxWithdrawUnderlying);

        vm.prank(holder);
        MetaVault(address(subMetaVault))
            .withdrawUnderlying(address(vault), stateBefore.maxWithdrawUnderlying, 0, holder, holder);
        // console.log("amountToWithdraw", amountToWithdraw);

        State memory stateAfter =
            _getMetaVaultState(subMetaVault, strategy, holder, SonicConstantsLib.WRAPPED_METAVAULT_METAUSDC);

        // ----------------------------------- check results
        assertApproxEqAbs(
            stateAfter.userBalanceUnderlying - stateBefore.userBalanceUnderlying,
            expectedUnderlying,
            1,
            "MetaUSDC: User receives expected underlying amount 1"
        );

        assertApproxEqAbs(
            stateBefore.strategyBalanceUnderlying - stateAfter.strategyBalanceUnderlying,
            expectedUnderlying,
            1,
            "MetaUSDC: strategy loss expected underlying amount 1"
        );

        assertApproxEqAbs(
            stateAfter.userBalanceMetaVaultTokens, 0, 1e6, "MetaUSDC: User should have no shares left after withdraw 1"
        );

        assertApproxEqAbs(
            stateBefore.internalSharePrice,
            stateAfter.internalSharePrice,
            stateBefore.internalSharePrice / 1e10,
            "MetaUSDC: internal share price should not change after withdraw underlying 1"
        );

        assertApproxEqAbs(
            stateAfter.userBalanceRecoveryToken - stateBefore.userBalanceRecoveryToken,
            stateBefore.userBalanceMetaVaultTokens - stateAfter.userBalanceMetaVaultTokens,
            1, // user always has 1 meta vault because of some rounding issues
            "MetaUSDC: User should receive expected amount of recovery tokens 1"
        );

        assertEq(
            stateAfter.userBalanceRecoveryToken - stateBefore.userBalanceRecoveryToken,
            IERC20(recoveryToken).totalSupply(),
            "MetaUSDC: All recovery tokens should be minted to the user 1"
        );

        assertEq(stateAfter.wrappedPrice, stateBefore.wrappedPrice, "MetaUSDC: wrapped price shouldn't change 1");
    }

    /// @dev MetaUSDC.withdrawUnderlyingEmergency => cVault
    function testWithdrawUnderlyingEmergencyMetaUsdcAMF() public {
        // ----------------------------------- upgrade vaults and strategies
        vm.prank(multisig);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);

        IMetaVault subMetaVault = IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);
        IStabilityVault vault = IStabilityVault(SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA0);

        _upgradeAmfStrategy(address(IVault(SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA0).strategy()));
        _upgradeCVault(SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA0);

        // ----------------------------------- set up recovery tokens
        address recoveryToken = _createRecoveryToken(address(subMetaVault), bytes32(uint(0x555)));
        vm.prank(multisig);
        subMetaVault.setRecoveryToken(address(vault), address(recoveryToken));

        // ----------------------------------- detect underlying and amount to withdraw
        IStrategy strategy = IVault(address(vault)).strategy();

        vm.prank(multisig);
        AaveMerklFarmStrategy(address(strategy)).setUnderlying();

        assertNotEq(strategy.underlying(), address(0), "AMF: Underlying should not be zero address 12");

        // ----------------------------------- withdraw all underlying
        address[] memory assets = new address[](1);
        assets[0] = strategy.underlying();

        address holder = HOLDER_META_USDC;

        State memory stateBefore =
            _getMetaVaultState(subMetaVault, strategy, holder, SonicConstantsLib.WRAPPED_METAVAULT_METAUSDC);
        uint expectedUnderlying = _getExpectedUnderlying(strategy, subMetaVault, stateBefore.maxWithdrawUnderlying);

        {
            address[] memory owners = new address[](1);
            owners[0] = holder;

            uint[] memory amounts = new uint[](1);
            amounts[0] = stateBefore.maxWithdrawUnderlying;

            uint[] memory minUnderlyingOut = new uint[](1);
            minUnderlyingOut[0] = expectedUnderlying;

            bool[] memory paused = new bool[](1);

            vm.prank(multisig);
            MetaVault(address(subMetaVault))
                .withdrawUnderlyingEmergency(address(vault), owners, amounts, minUnderlyingOut, paused);
        }
        // console.log("amountToWithdraw", amountToWithdraw);

        State memory stateAfter =
            _getMetaVaultState(subMetaVault, strategy, holder, SonicConstantsLib.WRAPPED_METAVAULT_METAUSDC);

        // ----------------------------------- check results
        assertApproxEqAbs(
            stateAfter.userBalanceUnderlying - stateBefore.userBalanceUnderlying,
            expectedUnderlying,
            1,
            "MetaUSDC: User receives expected underlying amount 2"
        );

        assertApproxEqAbs(
            stateBefore.strategyBalanceUnderlying - stateAfter.strategyBalanceUnderlying,
            expectedUnderlying,
            1,
            "MetaUSDC: strategy loss expected underlying amount 2"
        );

        assertApproxEqAbs(
            stateAfter.userBalanceMetaVaultTokens, 0, 1e6, "MetaUSDC: User should have no shares left after withdraw 2"
        );

        assertApproxEqAbs(
            stateBefore.internalSharePrice,
            stateAfter.internalSharePrice,
            stateBefore.internalSharePrice / 1e10,
            "MetaUSDC: internal share price should not change after withdraw underlying 2"
        );

        assertApproxEqAbs(
            stateAfter.userBalanceRecoveryToken - stateBefore.userBalanceRecoveryToken,
            stateBefore.userBalanceMetaVaultTokens - stateAfter.userBalanceMetaVaultTokens,
            1, // user always has 1 meta vault because of some rounding issues
            "MetaUSDC: User should receive expected amount of recovery tokens 2"
        );

        assertEq(
            stateAfter.userBalanceRecoveryToken - stateBefore.userBalanceRecoveryToken,
            IERC20(recoveryToken).totalSupply(),
            "MetaUSDC: All recovery tokens should be minted to the user 2"
        );

        assertEq(stateAfter.wrappedPrice, stateBefore.wrappedPrice, "MetaUSDC: wrapped price shouldn't change 2");
    }

    //endregion --------------------------------------- Tests for MetaUSDC/MetaScUSD (sub-meta-vaults)

    //region --------------------------------------- Tests for MetaUSD
    /// @dev MetaUSD.withdrawUnderlying => MetaUSDC => CVault
    function testWithdrawUnderlyingMetaUsdAMF() public {
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METASCUSD);

        IMetaVault _metaVault = IMetaVault(SonicConstantsLib.METAVAULT_METAUSD);

        (, IStabilityVault vault) =
            _prepareSubVaultToDeposit(SonicConstantsLib.METAVAULT_METAUSDC, SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA0);
        _upgradeAmfStrategy(address(IVault(SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA0).strategy()));
        _upgradeCVault(SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA0);

        // ----------------------------------- set up recovery tokens
        (address recoveryToken, address recoveryTokenMetaUSDC,) = _setUpRecoveryTokenMetaUsd(vault);

        // ----------------------------------- detect underlying and amount to withdraw
        IStrategy strategy = IVault(address(vault)).strategy();

        vm.prank(multisig);
        AaveMerklFarmStrategy(address(strategy)).setUnderlying();

        assertNotEq(strategy.underlying(), address(0), "AMF: Underlying should not be zero address 3");

        address holder = LARGEST_META_USD_HOLDERS[5];

        // ----------------------------------- withdraw all underlying
        State memory stateBefore =
            _getMetaVaultState(_metaVault, strategy, holder, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);
        uint expectedUnderlying = _getExpectedUnderlying(strategy, _metaVault, stateBefore.maxWithdrawUnderlying);

        vm.prank(holder);
        MetaVault(address(_metaVault))
            .withdrawUnderlying(address(vault), stateBefore.maxWithdrawUnderlying, 0, holder, holder);

        State memory stateAfter =
            _getMetaVaultState(_metaVault, strategy, holder, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);

        // ----------------------------------- check results
        assertApproxEqAbs(
            stateAfter.userBalanceUnderlying - stateBefore.userBalanceUnderlying,
            expectedUnderlying,
            1,
            "MetaUSDC: User receives expected underlying amount 1"
        );

        assertApproxEqAbs(
            stateBefore.strategyBalanceUnderlying - stateAfter.strategyBalanceUnderlying,
            expectedUnderlying,
            1,
            "MetaUSDC: strategy loss expected underlying amount 1"
        );

        assertApproxEqAbs(
            stateAfter.userBalanceMetaVaultTokens, 0, 1e6, "MetaUSDC: User should have no shares left after withdraw 1"
        );

        assertApproxEqAbs(
            stateBefore.internalSharePrice,
            stateAfter.internalSharePrice,
            stateBefore.internalSharePrice / 1e10,
            "MetaUSDC: internal share price should not change after withdraw underlying 1"
        );

        assertApproxEqAbs(
            stateAfter.userBalanceRecoveryToken - stateBefore.userBalanceRecoveryToken,
            stateBefore.userBalanceMetaVaultTokens - stateAfter.userBalanceMetaVaultTokens,
            1, // user always has 1 meta vault because of some rounding issues
            "MetaUSDC: User should receive expected amount of recovery tokens 1"
        );

        assertEq(
            stateAfter.userBalanceRecoveryToken - stateBefore.userBalanceRecoveryToken,
            IERC20(recoveryToken).totalSupply(),
            "MetaUSDC: All recovery tokens should be minted to the user 1"
        );

        assertEq(stateAfter.wrappedPrice, stateBefore.wrappedPrice, "MetaUSDC: wrapped price shouldn't change 1");

        assertEq(
            IERC20(recoveryTokenMetaUSDC).totalSupply(), 0, "MetaUSDC: sub vault shouldn't mint its recovery tokens"
        );
    }

    /// @dev Bad paths for MetaUSD.withdrawUnderlying => MetaUSDC => CVault
    function testWithdrawUnderlyingMetaUsdBadPaths() public {
        // ---------------------------- prepare to deposit
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METASCUSD);

        IMetaVault _metaVault = IMetaVault(SonicConstantsLib.METAVAULT_METAUSD);

        (, IStabilityVault vault) =
            _prepareSubVaultToDeposit(SonicConstantsLib.METAVAULT_METAUSDC, SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA0);
        _upgradeAmfStrategy(address(IVault(SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA0).strategy()));
        _upgradeCVault(SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA0);

        IStrategy strategy = IVault(address(vault)).strategy();

        vm.prank(multisig);
        AaveMerklFarmStrategy(address(strategy)).setUnderlying();

        // ----------------------------------- set up recovery tokens
        _setUpRecoveryTokenMetaUsd(vault);

        // --------------------------- prepare to withdraw
        address holder = SonicConstantsLib.WRAPPED_METAVAULT_METAUSD;
        uint amountToWithdraw = _metaVault.maxWithdrawUnderlying(address(vault), holder);

        //---------------------------- try to withdraw without allowance
        {
            uint snapshot = vm.snapshotState();

            // vm.expectRevert(IERC20Errors.ERC20InsufficientAllowance.selector);
            vm.prank(user2);
            try MetaVault(address(_metaVault)).withdrawUnderlying(address(vault), amountToWithdraw, 0, user2, holder) {
                require(false, "Error IERC20Errors.ERC20InsufficientAllowance wasn't thrown");
            } catch (bytes memory reason) {
                require(
                    reason.length >= 4 && bytes4(reason) == IERC20Errors.ERC20InsufficientAllowance.selector,
                    "Some other error was thrown instead of ERC20InsufficientAllowance"
                );
            }

            vm.prank(holder);
            IERC20(_metaVault).approve(user2, amountToWithdraw);

            vm.prank(user2);
            uint underlyingOut =
                MetaVault(address(_metaVault)).withdrawUnderlying(address(vault), amountToWithdraw, 0, user2, holder);

            assertEq(
                underlyingOut, IERC20(strategy.underlying()).balanceOf(user2), "Withdrawn amount should be correct"
            );
            assertNotEq(underlyingOut, 0, "User 2 should receive some underlying");

            vm.revertToState(snapshot);
        }

        //---------------------------- try to withdraw with zero balance
        {
            uint snapshot = vm.snapshotState();

            vm.expectRevert(IControllable.IncorrectZeroArgument.selector);
            vm.prank(holder);
            MetaVault(address(_metaVault)).withdrawUnderlying(address(vault), 0, 0, holder, holder);

            vm.revertToState(snapshot);
        }

        //---------------------------- try to withdraw more than balance
        {
            uint snapshot = vm.snapshotState();

            // vm.expectRevert(IERC20Errors.ERC20InsufficientBalance.selector);
            vm.prank(user2);
            try MetaVault(address(_metaVault)).withdrawUnderlying(address(vault), amountToWithdraw, 0, user2, user2) {
                require(false, "Error IERC20Errors.ERC20InsufficientBalance wasn't thrown");
            } catch (bytes memory reason) {
                require(
                    reason.length >= 4 && bytes4(reason) == IERC20Errors.ERC20InsufficientBalance.selector,
                    "Some other error was thrown instead of ERC20InsufficientBalance"
                );
            }

            vm.revertToState(snapshot);
        }

        // --------------------------- try to withdraw too low
        {
            uint snapshot = vm.snapshotState();

            vm.expectRevert(abi.encodeWithSelector(IMetaVault.ZeroSharesToBurn.selector, 1));
            vm.prank(holder);
            MetaVault(address(_metaVault)).withdrawUnderlying(address(vault), 1, 0, holder, holder);

            vm.revertToState(snapshot);
        }

        // --------------------------- try to withdraw from a vault that doesn't belong to the MetaVault
        {
            uint snapshot = vm.snapshotState();
            _upgradeCVault(SonicConstantsLib.VAULT_C_USDC_S_34);
            _upgradeSiloStrategy(address(IVault(SonicConstantsLib.VAULT_C_USDC_S_34).strategy()));

            vm.expectRevert(
                abi.encodeWithSelector(IMetaVault.VaultNotFound.selector, SonicConstantsLib.VAULT_C_USDC_S_34)
            );
            vm.prank(holder);
            MetaVault(address(_metaVault))
                .withdrawUnderlying(SonicConstantsLib.VAULT_C_USDC_S_34, 1e18, 0, holder, holder);

            vm.revertToState(snapshot);
        }
    }

    /// @dev MetaUSD.withdrawUnderlying => MetaScUSD => CVault
    function testWithdrawUnderlyingMetaScUsd() public {
        // ---------------------------- prepare to deposit
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METASCUSD);

        IMetaVault _metaVault = IMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        IStabilityVault vault = IStabilityVault(SonicConstantsLib.VAULT_C_CREDIX_SCUSD_AMFA0);

        _upgradeAmfStrategy(address(IVault(address(vault)).strategy()));
        _upgradeCVault(address(vault));

        IStrategy strategy = IVault(address(vault)).strategy();

        vm.prank(multisig);
        AaveMerklFarmStrategy(address(strategy)).setUnderlying();

        // ----------------------------------- set up recovery tokens
        _setUpRecoveryTokenMetaUsd(vault);

        // --------------------------- TooHighAmount
        {
            uint snapshot = vm.snapshotState();

            address holder = SonicConstantsLib.WRAPPED_METAVAULT_METAUSD;
            uint holderBalance = _metaVault.balanceOf(holder);
            uint maxWithdrawUnderlying = _metaVault.maxWithdrawUnderlying(address(vault), holder);
            uint maxWithdraw = _metaVault.maxWithdraw(holder);
            assertLt(
                maxWithdraw, maxWithdrawUnderlying, "Meta vault doesn't have enough liquidity after credix incident"
            );

            // vm.expectRevert(abi.encodeWithSelector(IMetaVault.TooHighAmount.selector));
            vm.prank(holder);
            try MetaVault(address(_metaVault))
                .withdrawUnderlying(address(vault), maxWithdrawUnderlying + 1, 0, holder, holder) {
                require(false, "Error IMetaVault.TooHighAmount wasn't thrown");
            } catch (bytes memory reason) {
                require(
                    reason.length >= 4 && bytes4(reason) == IMetaVault.TooHighAmount.selector,
                    "Some other error was thrown instead of IMetaVault.TooHighAmount"
                );
            }

            uint expectedUnderlying = _getExpectedUnderlying(strategy, _metaVault, maxWithdrawUnderlying);

            vm.prank(holder);
            uint withdrawn = MetaVault(address(_metaVault))
                .withdrawUnderlying(address(vault), maxWithdrawUnderlying, 0, holder, holder);

            assertApproxEqAbs(withdrawn, expectedUnderlying, 1, "Withdrawn amount should match expected value 4");
            assertApproxEqAbs(
                holderBalance - _metaVault.balanceOf(holder),
                maxWithdrawUnderlying,
                1,
                "Holder should have correct balance after withdraw 4"
            );

            vm.revertToState(snapshot);
        }
    }

    /// @dev multisig => MetaUSD.withdrawUnderlyingEmergency => MetaUSDC => CVault
    function testMetaVaultWithdrawUnderlyingEmergencyByMultisig() public {
        // ---------------------------- set up contracts
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METASCUSD);

        IMetaVault _metaVault = IMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        IVault vault = IVault(SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA0);

        _upgradeAmfStrategy(address(vault.strategy()));
        _upgradeCVault(address(vault));

        IStrategy strategy = IVault(address(vault)).strategy();

        vm.prank(multisig);
        AaveMerklFarmStrategy(address(strategy)).setUnderlying();

        // ----------------------------------- set up recovery tokens
        (address recoveryToken, address recoveryTokenMetaUSDC,) = _setUpRecoveryTokenMetaUsd(vault);

        // --------------------------- prepare to withdraw underlying in emergency
        (ArraysForMetaVault memory ar, MultiState memory stateBefore) = _getArraysForMetaUSD(_metaVault, strategy);
        uint count = ar.owners.length;

        // --------------------------- withdraw underlying in emergency by gov (success)
        uint gas = gasleft();
        vm.prank(multisig);
        (uint[] memory amountsOut, uint[] memory recoveryAmountOut) =
            _metaVault.withdrawUnderlyingEmergency(address(vault), ar.owners, ar.amounts, ar.minAmountsOut, ar.paused);

        assertLt(gas - gasleft(), 10e6, "Gas used for withdrawUnderlyingEmergency should be less than 10M 5");

        MultiState memory stateAfter =
            _getMetaVaultMultiState(_metaVault, strategy, ar.owners, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);

        // ----------------------------------- check results
        for (uint i = 0; i < count; ++i) {
            // console.log("i, amountOut", i, amountsOut[i]);
            assertApproxEqAbs(amountsOut[i], ar.minAmountsOut[i], 1, "Withdrawn amount should match expected value 5");
        }

        {
            uint expectedUnderlyingTotal;
            for (uint i = 0; i < count; ++i) {
                expectedUnderlyingTotal += ar.expectedUnderlying[i];
            }

            assertApproxEqAbs(
                stateBefore.strategyBalanceUnderlying - stateAfter.strategyBalanceUnderlying,
                expectedUnderlyingTotal,
                count, // 1 decimal per user
                "MetaUSDC: strategy loss expected underlying amount 4"
            );
        }

        for (uint i; i < count; ++i) {
            assertApproxEqAbs(
                stateAfter.userBalanceUnderlying[i] - stateBefore.userBalanceUnderlying[i],
                ar.expectedUnderlying[i],
                1,
                "MetaUSD: User receives expected underlying amount 4"
            );

            assertApproxEqAbs(
                stateAfter.userBalanceMetaVaultTokens[i],
                0,
                1e6,
                "MetaUSD: User should have no shares left after withdraw 4"
            );

            assertApproxEqAbs(
                stateAfter.userBalanceRecoveryToken[i] - stateBefore.userBalanceRecoveryToken[i],
                stateBefore.userBalanceMetaVaultTokens[i] - stateAfter.userBalanceMetaVaultTokens[i],
                1, // user always has 1 meta vault because of some rounding issues
                "MetaUSD: User should receive expected amount of recovery tokens 4"
            );

            assertEq(
                stateAfter.userBalanceRecoveryToken[i] - stateBefore.userBalanceRecoveryToken[i],
                recoveryAmountOut[i],
                "MetaUSD: User should receive declared amount of recovery tokens 4"
            );

            assertEq(
                IRecoveryToken(recoveryToken).paused(ar.owners[i]),
                i % 2 == 0,
                "MetaUSD: Recovery token should be paused for even users"
            );
        }

        assertApproxEqAbs(
            stateBefore.internalSharePrice,
            stateAfter.internalSharePrice,
            stateBefore.internalSharePrice / 1e10,
            "MetaUSD: internal share price should not change after withdraw underlying 4"
        );

        assertEq(
            stateAfter.userBalanceRecoveryTokenTotal - stateBefore.userBalanceRecoveryTokenTotal,
            IERC20(recoveryToken).totalSupply(),
            "MetaUSD: All recovery tokens should be minted to the users"
        );

        assertEq(stateAfter.wrappedPrice, stateBefore.wrappedPrice, "MetaUSD: wrapped price shouldn't change 1");

        assertEq(
            IERC20(recoveryTokenMetaUSDC).totalSupply(), 0, "MetaUSD: sub vault shouldn't mint its recovery tokens"
        );

        assertApproxEqAbs(
            stateAfter.metaVaultBalanceUnderlying, 0, count, "MetaUSD: metavault shouldn't have underlying 1"
        );
    }

    /// @dev WMetaUSD => MetaUSD.withdrawUnderlyingEmergency => MetaUSDC => CVault
    function testMetaVaultWithdrawUnderlyingEmergencyByWrapped() public {
        // ---------------------------- set up contracts
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METASCUSD);

        IMetaVault _metaVault = IMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        IVault vault = IVault(SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA0);

        _upgradeAmfStrategy(address(vault.strategy()));
        _upgradeCVault(address(vault));

        IStrategy strategy = IVault(address(vault)).strategy();

        vm.prank(multisig);
        AaveMerklFarmStrategy(address(strategy)).setUnderlying();

        // ----------------------------------- set up recovery tokens
        (address recoveryToken, address recoveryTokenMetaUSDC,) = _setUpRecoveryTokenMetaUsd(vault);

        // --------------------------- prepare to withdraw underlying in emergency
        (ArraysForMetaVault memory ar, MultiState memory stateBefore) = _getArraysForMetaUSD(_metaVault, strategy);
        uint count = ar.owners.length;

        // --------------------------- withdraw underlying in emergency by metavault (success)
        address caller = SonicConstantsLib.WRAPPED_METAVAULT_METAUSD;
        vm.prank(multisig);
        _metaVault.changeWhitelist(caller, true);

        uint gas = gasleft();
        vm.prank(caller);
        (uint[] memory amountsOut, uint[] memory recoveryAmountOut) =
            _metaVault.withdrawUnderlyingEmergency(address(vault), ar.owners, ar.amounts, ar.minAmountsOut, ar.paused);

        assertLt(gas - gasleft(), 10e6, "Gas used for withdrawUnderlyingEmergency should be less than 10M 5");

        MultiState memory stateAfter =
            _getMetaVaultMultiState(_metaVault, strategy, ar.owners, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);

        // ----------------------------------- check results
        for (uint i = 0; i < count; ++i) {
            // console.log("i, amountOut", i, amountsOut[i]);
            assertApproxEqAbs(amountsOut[i], ar.minAmountsOut[i], 1, "Withdrawn amount should match expected value 5");
        }

        {
            uint expectedUnderlyingTotal;
            for (uint i = 0; i < count; ++i) {
                expectedUnderlyingTotal += ar.expectedUnderlying[i];
            }

            assertApproxEqAbs(
                stateBefore.strategyBalanceUnderlying - stateAfter.strategyBalanceUnderlying,
                expectedUnderlyingTotal,
                count, // 1 decimal per user
                "MetaUSDC: strategy loss expected underlying amount 4"
            );
        }

        for (uint i; i < count; ++i) {
            assertApproxEqAbs(
                stateAfter.userBalanceUnderlying[i] - stateBefore.userBalanceUnderlying[i],
                ar.expectedUnderlying[i],
                1,
                "MetaUSD: User receives expected underlying amount 5"
            );

            assertApproxEqAbs(
                stateAfter.userBalanceMetaVaultTokens[i],
                0,
                1e6,
                "MetaUSD: User should have no shares left after withdraw 5"
            );

            assertApproxEqAbs(
                stateAfter.userBalanceRecoveryToken[i] - stateBefore.userBalanceRecoveryToken[i],
                0,
                1, // user always has 1 meta vault because of some rounding issues
                "MetaUSD shouldn't mint recovery tokens 5"
            );

            assertEq(
                stateAfter.userBalanceRecoveryToken[i] - stateBefore.userBalanceRecoveryToken[i],
                recoveryAmountOut[i],
                "MetaUSD: User should receive declared amount of recovery tokens 5"
            );

            assertEq(
                IRecoveryToken(recoveryToken).paused(ar.owners[i]),
                false,
                "MetaUSD: Recovery token should not be paused for any users (no recovery tokens minted)"
            );
        }

        assertApproxEqAbs(
            stateBefore.internalSharePrice,
            stateAfter.internalSharePrice,
            stateBefore.internalSharePrice / 1e10,
            "MetaUSD: internal share price should not change after withdraw underlying 5"
        );

        assertEq(IERC20(recoveryToken).totalSupply(), 0, "MetaUSD should mint zero recovery tokens");

        assertEq(stateAfter.wrappedPrice, stateBefore.wrappedPrice, "MetaUSD: wrapped price shouldn't change 1");

        assertEq(
            IERC20(recoveryTokenMetaUSDC).totalSupply(), 0, "MetaUSD: sub vault shouldn't mint its recovery tokens"
        );
    }

    /// @dev Bad paths for MetaUSD.withdrawUnderlyingEmergency => MetaUSDC => CVault
    function testMetaVaultWithdrawUnderlyingEmergencyBadPaths() public {
        // ---------------------------- set up contracts
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METASCUSD);

        IMetaVault _metaVault = IMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        IVault vault = IVault(SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA0);

        _upgradeAmfStrategy(address(vault.strategy()));
        _upgradeCVault(address(vault));

        IStrategy strategy = IVault(address(vault)).strategy();

        vm.prank(multisig);
        AaveMerklFarmStrategy(address(strategy)).setUnderlying();

        // ----------------------------------- set up recovery tokens
        _setUpRecoveryTokenMetaUsd(vault);

        // --------------------------- prepare to withdraw underlying in emergency
        (ArraysForMetaVault memory ar,) = _getArraysForMetaUSD(_metaVault, strategy);
        uint count = ar.owners.length;

        // --------------------------- fail to withdraw: not multisig
        {
            uint snapshot = vm.snapshotState();

            vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
            vm.prank(address(this));
            _metaVault.withdrawUnderlyingEmergency(address(vault), ar.owners, ar.amounts, ar.minAmountsOut, ar.paused);

            vm.revertToState(snapshot);
        }

        // --------------------------- fail to withdraw: zero balance
        {
            uint snapshot = vm.snapshotState();

            address[] memory owners2 = new address[](count);
            for (uint i = 0; i < count; ++i) {
                owners2[i] = i == 0
                    ? address(this)  // (!) "this" has no meta vault tokens
                    : LARGEST_META_USD_HOLDERS[i];
            }

            vm.expectRevert(IControllable.IncorrectBalance.selector);
            vm.prank(multisig);
            _metaVault.withdrawUnderlyingEmergency(address(vault), owners2, ar.amounts, ar.minAmountsOut, ar.paused);

            vm.revertToState(snapshot);
        }

        // --------------------------- fail to withdraw: ZeroSharesToBurn
        {
            uint snapshot = vm.snapshotState();

            uint[] memory amounts2 = new uint[](count);
            for (uint i = 0; i < count; ++i) {
                amounts2[i] = i == 0
                    ? 1  // (!) ask for 1 decimal only, so it should fail with ZeroSharesToBurn
                    : 0; // by default withdraw all
            }

            vm.expectRevert(abi.encodeWithSelector(IMetaVault.ZeroSharesToBurn.selector, 1));
            vm.prank(multisig);
            _metaVault.withdrawUnderlyingEmergency(address(vault), ar.owners, amounts2, ar.minAmountsOut, ar.paused);

            vm.revertToState(snapshot);
        }

        // --------------------------- fail to withdraw: nothing to withdraw
        {
            uint snapshot = vm.snapshotState();

            vm.expectRevert(IControllable.IncorrectZeroArgument.selector);
            vm.prank(multisig);
            _metaVault.withdrawUnderlyingEmergency(
                address(vault), new address[](0), new uint[](0), new uint[](0), new bool[](0)
            );

            vm.revertToState(snapshot);
        }

        // --------------------------- fail to withdraw: different lengths
        {
            uint snapshot = vm.snapshotState();

            vm.expectRevert(IControllable.IncorrectArrayLength.selector);
            vm.prank(multisig);
            _metaVault.withdrawUnderlyingEmergency(address(vault), ar.owners, ar.amounts, new uint[](0), ar.paused);

            vm.expectRevert(IControllable.IncorrectArrayLength.selector);
            vm.prank(multisig);
            _metaVault.withdrawUnderlyingEmergency(
                address(vault), ar.owners, new uint[](0), ar.minAmountsOut, ar.paused
            );

            vm.expectRevert(IControllable.IncorrectArrayLength.selector);
            vm.prank(multisig);
            _metaVault.withdrawUnderlyingEmergency(
                address(vault), new address[](0), ar.amounts, ar.minAmountsOut, ar.paused
            );

            vm.expectRevert(IControllable.IncorrectArrayLength.selector);
            vm.prank(multisig);
            _metaVault.withdrawUnderlyingEmergency(
                address(vault), ar.owners, ar.amounts, ar.minAmountsOut, new bool[](0)
            );

            vm.revertToState(snapshot);
        }

        // --------------------------- fail to withdraw: slippage
        {
            uint snapshot = vm.snapshotState();

            uint[] memory minAmountsOut2 = new uint[](count);
            for (uint i = 0; i < count; ++i) {
                minAmountsOut2[i] = i == 0 ? ar.minAmountsOut[i] + 2 : ar.minAmountsOut[i];
            }

            // vm.expectRevert(IStabilityVault.ExceedSlippage.selector);
            vm.prank(multisig);
            try _metaVault.withdrawUnderlyingEmergency(
                address(vault), ar.owners, ar.amounts, minAmountsOut2, ar.paused
            ) {
                require(false, "Error IStabilityVault.ExceedSlippage wasn't thrown 5");
            } catch (bytes memory reason) {
                require(
                    reason.length >= 4 && bytes4(reason) == IStabilityVault.ExceedSlippage.selector,
                    "Some other error was thrown instead of IStabilityVault.ExceedSlippage 5"
                );
            }

            vm.revertToState(snapshot);
        }

        //---------------------------- try to withdraw from not-broken vault
        {
            uint snapshot = vm.snapshotState();

            vm.prank(multisig);
            _metaVault.setRecoveryToken(address(vault), address(0)); // (!) make c-vault is not broken

            vm.expectRevert(abi.encodeWithSelector(IMetaVault.RecoveryTokenNotSet.selector, address(vault)));
            vm.prank(multisig);
            _metaVault.withdrawUnderlyingEmergency(address(vault), ar.owners, ar.amounts, ar.minAmountsOut, ar.paused);

            vm.revertToState(snapshot);
        }

        //---------------------------- try to withdraw too much for the user
        {
            uint snapshot = vm.snapshotState();

            uint[] memory amounts2 = new uint[](count);
            for (uint i = 0; i < count; ++i) {
                amounts2[i] = _metaVault.maxWithdrawUnderlying(address(vault), ar.owners[i]) + 1; // ask for more than max withdraw
            }

            // vm.expectRevert(IERC20Errors.ERC20InsufficientBalance.selector);
            vm.prank(multisig);
            try _metaVault.withdrawUnderlyingEmergency(
                address(vault), ar.owners, amounts2, ar.minAmountsOut, ar.paused
            ) {
                require(false, "Error IERC20Errors.ERC20InsufficientBalance wasn't thrown");
            } catch (bytes memory reason) {
                require(
                    reason.length >= 4 && bytes4(reason) == IERC20Errors.ERC20InsufficientBalance.selector,
                    "Some other error was thrown instead of ERC20InsufficientBalance"
                );
            }

            vm.revertToState(snapshot);
        }
    }

    //endregion --------------------------------------- Tests for MetaUSD

    //region --------------------------------------- Tests for WrappedMetaUSD
    /// @dev WrappedMetaVault.redeemUnderlyingEmergency => MetaUSD => MetaUSDC => CVault
    function testWrappedWithdrawUnderlyingEmergencyHappyPaths() public {
        // ---------------------------- set up contracts
        WrappedMetaVault _wrappedMetaVault = WrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);

        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METASCUSD);
        _upgradeWrappedMetaVault();

        // ---------------------------- set up c-vault 1
        IVault vault1 = IVault(SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA0);
        _upgradeAmfStrategy(address(vault1.strategy()));
        _upgradeCVault(address(vault1));
        {
            IStrategy strategy1 = IVault(address(vault1)).strategy();

            vm.prank(multisig);
            AaveMerklFarmStrategy(address(strategy1)).setUnderlying();
        }

        // ---------------------------- set up c-vault 2
        IVault vault2 = IVault(SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA5);
        _upgradeAmfStrategy(address(vault2.strategy()));
        _upgradeCVault(address(vault2));
        {
            IStrategy strategy2 = IVault(address(vault2)).strategy();

            vm.prank(multisig);
            AaveMerklFarmStrategy(address(strategy2)).setUnderlying();
        }

        // --------------------------- set up recovery tokens and whitelist
        address[4] memory recoveryTokens = _setUpRecoveryTokenWrapped([address(vault1), address(vault2)]);

        // --------------------------- state before withdrawing
        WrappedState memory stateBefore = _getWrappedState(vault2, _wrappedMetaVault);

        // --------------------------- withdraw underlying in emergency (vault 1)
        uint[] memory recoveryAmountOut1;
        {
            (ArraysForWrapped memory ar,) = _getArraysForWrapped(_wrappedMetaVault, vault1, 1, false);
            uint count = ar.owners.length;

            uint[] memory amountsOut;

            uint gas = gasleft();
            vm.prank(multisig);
            (amountsOut, recoveryAmountOut1) = _wrappedMetaVault.redeemUnderlyingEmergency(
                address(vault1), ar.owners, ar.shares, ar.minAmountsOut, ar.paused
            );

            assertLt(gas - gasleft(), 15e6, "Gas used for withdrawUnderlyingEmergency should be less than 15M 6");

            for (uint i = 0; i < count; ++i) {
                // console.log("i, amountOut", i, amountsOut[i]);
                assertApproxEqAbs(
                    amountsOut[i], ar.minAmountsOut[i], 2e3, "Withdrawn amount should match expected value 6"
                );
            }
        }

        WrappedState memory stateMiddle = _getWrappedState(vault2, _wrappedMetaVault);

        // --------------------------- withdraw underlying in emergency (vault 2), check balances and wrapped state
        {
            (ArraysForWrapped memory ar,) =
                _getArraysForWrapped(_wrappedMetaVault, vault1, LARGEST_WRAPPED_META_USD_HOLDERS.length, true);
            uint count = ar.owners.length;

            uint gas = gasleft();
            vm.prank(multisig);
            (uint[] memory amountsOut, uint[] memory recoveryAmountOut2) = _wrappedMetaVault.redeemUnderlyingEmergency(
                address(vault2), ar.owners, ar.shares, ar.minAmountsOut, ar.paused
            );

            assertLt(gas - gasleft(), 15e6, "Gas used for withdrawUnderlyingEmergency should be less than 15M 7");

            // --------------------------- state after withdrawing
            WrappedState memory stateAfter = _getWrappedState(vault2, _wrappedMetaVault);

            // --------------------------- check amount out
            for (uint i = 0; i < count; ++i) {
                // console.log("i, amountOut", i, amountsOut[i], owners[i]);
                assertApproxEqAbs(
                    amountsOut[i], ar.minAmountsOut[i], 2e3, "Withdrawn amount should match expected value 7"
                );
                stateBefore.totalAmountsOut += amountsOut[i];
            }

            // --------------------------- check results
            for (uint i = 0; i < count; ++i) {
                assertApproxEqAbs(
                    IERC20(vault2.strategy().underlying()).balanceOf(ar.owners[i])
                        - stateBefore.userBalanceUnderlying[i],
                    amountsOut[i],
                    1,
                    "Owner should receive correct amount of underlying of vault2 7"
                );

                assertApproxEqAbs(stateAfter.userBalancesWrapped[i], 0, 1, "Owner should spend all wrapped shares 7");

                assertApproxEqAbs(
                    i == 0 ? recoveryAmountOut1[i] + recoveryAmountOut2[i] : recoveryAmountOut2[i],
                    stateAfter.userBalanceRecoveryToken[i],
                    1,
                    "Owner should receive expected amount of recovery tokens 7"
                );

                for (uint j = 1; j < recoveryTokens.length; ++j) {
                    assertEq(
                        IERC20(recoveryTokens[j]).balanceOf(ar.owners[i]),
                        0,
                        "Owner should NOT receive any recovery tokens except wrapped's one 7"
                    );
                }

                assertEq(
                    IRecoveryToken(recoveryTokens[0]).paused(ar.owners[i]),
                    i % 2 == 0,
                    "WMetaUSD: Recovery token should be paused for even users"
                );
            }

            assertEq(stateBefore.wrappedPrice, stateAfter.wrappedPrice, "Wrapped price should not change 7");

            assertApproxEqAbs(
                stateBefore.totalSupply - stateAfter.totalSupply,
                stateBefore.totalShares,
                1,
                "Total supply should decrease by total shares withdrawn 7"
            );

            (uint priceAsset,) = IPriceReader(IPlatform(PLATFORM).priceReader())
                .getPrice(IAToken(vault2.strategy().underlying()).UNDERLYING_ASSET_ADDRESS());
            assertApproxEqAbs(
                (stateMiddle.totalAssets - stateAfter.totalAssets), // meta vault tokens, usd 18
                stateBefore.totalAmountsOut * priceAsset / 10
                    ** IERC20Metadata(vault2.strategy().underlying()).decimals(), // usd 18
                1e13, // < 1e-5 usd
                "Total assets should decrease by total amounts out withdrawn 7"
            );

            for (uint i = 1; i < 4; ++i) {
                assertEq(IERC20(recoveryTokens[i]).totalSupply(), 0, "Only wrapped recovery token should be minted 7");
            }

            assertApproxEqAbs(
                stateBefore.totalAssets - stateAfter.totalAssets,
                stateAfter.totalSupplyRecoveryToken,
                1e11, // rounding error
                "Expected amount of wrapped recovery tokens were minted 7"
            );

            assertApproxEqAbs(
                stateBefore.strategyBalanceUnderlying - stateAfter.strategyBalanceUnderlying,
                stateBefore.totalAmountsOut + stateAfter.wrappedBalanceUnderlying,
                1,
                "Strategy should lose expected amount of underlying 7"
            );

            assertLt(stateAfter.wrappedBalanceUnderlying, 10, "Wrapped should have no underlying on balance 7");
        }
    }

    /// @dev WrappedMetaVault.redeemUnderlyingEmergency => MetaUSD => MetaUSDC => CVault (bad paths)
    function testWrappedWithdrawUnderlyingEmergencyBadPaths() public {
        // ---------------------------- set up contracts
        WrappedMetaVault _wrappedMetaVault = WrappedMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);

        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METASCUSD);
        _upgradeWrappedMetaVault();

        // ---------------------------- set up c-vault 1
        IVault vault1 = IVault(SonicConstantsLib.VAULT_C_CREDIX_USDC_AMFA0);
        _upgradeAmfStrategy(address(vault1.strategy()));
        _upgradeCVault(address(vault1));
        {
            IStrategy strategy1 = IVault(address(vault1)).strategy();

            vm.prank(multisig);
            AaveMerklFarmStrategy(address(strategy1)).setUnderlying();
        }

        // --------------------------- set up recovery tokens and whitelist
        _setUpRecoveryTokenWrapped([address(vault1), address(0)]);

        // --------------------------- prepare data
        (ArraysForWrapped memory ar,) = _getArraysForWrapped(_wrappedMetaVault, vault1, 1, false);

        // --------------------------- not multisig, not governance
        vm.expectRevert(IControllable.NotGovernanceAndNotMultisig.selector);
        vm.prank(address(this));
        _wrappedMetaVault.redeemUnderlyingEmergency(address(vault1), ar.owners, ar.shares, ar.minAmountsOut, ar.paused);

        // --------------------------- incorrect arrays
        vm.expectRevert(IControllable.IncorrectArrayLength.selector);
        vm.prank(multisig);
        _wrappedMetaVault.redeemUnderlyingEmergency(
            address(vault1), new address[](5), ar.shares, ar.minAmountsOut, ar.paused
        );

        vm.expectRevert(IControllable.IncorrectArrayLength.selector);
        vm.prank(multisig);
        _wrappedMetaVault.redeemUnderlyingEmergency(
            address(vault1), ar.owners, new uint[](5), ar.minAmountsOut, ar.paused
        );

        vm.expectRevert(IControllable.IncorrectArrayLength.selector);
        vm.prank(multisig);
        _wrappedMetaVault.redeemUnderlyingEmergency(address(vault1), ar.owners, ar.shares, new uint[](0), ar.paused);

        vm.expectRevert(IControllable.IncorrectArrayLength.selector);
        vm.prank(multisig);
        _wrappedMetaVault.redeemUnderlyingEmergency(
            address(vault1), ar.owners, ar.shares, ar.minAmountsOut, new bool[](0)
        );

        // --------------------------- incorrect balance (zero shares)
        {
            address[] memory wrongOwners = new address[](1);
            wrongOwners[0] = address(this);

            vm.expectRevert(IControllable.IncorrectBalance.selector);
            vm.prank(multisig);
            _wrappedMetaVault.redeemUnderlyingEmergency(
                address(vault1), wrongOwners, new uint[](1), new uint[](1), new bool[](1)
            );
        }

        // --------------------------- No recovery token
        {
            uint snapshot = vm.snapshotState();

            vm.prank(multisig);
            IMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD).setRecoveryToken(address(vault1), address(0));

            vm.expectRevert(abi.encodeWithSelector(IMetaVault.RecoveryTokenNotSet.selector, address(vault1)));
            vm.prank(multisig);
            _wrappedMetaVault.redeemUnderlyingEmergency(
                address(vault1), ar.owners, ar.shares, ar.minAmountsOut, ar.paused
            );

            vm.revertToState(snapshot);
        }

        // --------------------------- ERC4626ExceededMaxRedeem
        {
            uint snapshot = vm.snapshotState();

            uint[] memory shares2 = new uint[](1);
            shares2[0] = ar.shares[0] * 1000; // ask for more than max withdraw

            // vm.expectRevert(IControllable.IncorrectBalance.selector);
            vm.prank(multisig);
            try _wrappedMetaVault.redeemUnderlyingEmergency(
                address(vault1), ar.owners, shares2, ar.minAmountsOut, ar.paused
            ) {
                require(false, "Error ERC4626Upgradeable.ERC4626ExceededMaxRedeem wasn't thrown");
            } catch (bytes memory reason) {
                require(
                    reason.length >= 4 && bytes4(reason) == ERC4626Upgradeable.ERC4626ExceededMaxRedeem.selector,
                    "Some other error was thrown instead of ERC4626ExceededMaxRedeem"
                );
            }

            vm.revertToState(snapshot);
        }

        // --------------------------- ExceedSlippage
        {
            uint snapshot = vm.snapshotState();

            uint[] memory minAmountsOut2 = new uint[](1);
            minAmountsOut2[0] = ar.minAmountsOut[0] * 1000;

            // vm.expectRevert(IControllable.IncorrectBalance.selector);
            vm.prank(multisig);
            try _wrappedMetaVault.redeemUnderlyingEmergency(
                address(vault1), ar.owners, ar.shares, minAmountsOut2, ar.paused
            ) {
                require(false, "Error IStabilityVault.ExceedSlippage wasn't thrown");
            } catch (bytes memory reason) {
                require(
                    reason.length >= 4 && bytes4(reason) == IStabilityVault.ExceedSlippage.selector,
                    "Some other error was thrown instead of ExceedSlippage"
                );
            }

            vm.revertToState(snapshot);
        }
    }

    //endregion --------------------------------------- Tests for WrappedMetaUSD

    //region ---------------------------------------------- States
    function _getMetaVaultState(
        IMetaVault metaVault_,
        IStrategy strategy_,
        address user_,
        address wrapped
    ) internal view returns (State memory state) {
        state.totalSupply = metaVault_.totalSupply();
        (state.price,) = metaVault_.price();
        (state.internalSharePrice,,,) = metaVault_.internalSharePrice();
        state.strategyBalanceUnderlying = IERC20(strategy_.underlying()).balanceOf(address(strategy_));
        state.userBalanceMetaVaultTokens = metaVault_.balanceOf(user_);
        state.userBalanceUnderlying = IERC20(strategy_.underlying()).balanceOf(user_);
        state.userBalanceRecoveryToken = IERC20(metaVault_.recoveryToken(strategy_.vault())).balanceOf(user_);
        state.maxWithdrawUnderlying = metaVault_.maxWithdrawUnderlying(strategy_.vault(), user_);
        (state.wrappedPrice,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(wrapped);

        return state;
    }

    function _getMetaVaultMultiState(
        IMetaVault metaVault_,
        IStrategy strategy_,
        address[] memory owners,
        address wrapped
    ) internal view returns (MultiState memory state) {
        state.totalSupply = metaVault_.totalSupply();
        (state.price,) = metaVault_.price();
        (state.internalSharePrice,,,) = metaVault_.internalSharePrice();
        state.strategyBalanceUnderlying = IERC20(strategy_.underlying()).balanceOf(address(strategy_));
        (state.wrappedPrice,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(wrapped);

        state.userBalanceMetaVaultTokens = new uint[](owners.length);
        state.userBalanceUnderlying = new uint[](owners.length);
        state.userBalanceRecoveryToken = new uint[](owners.length);
        state.maxWithdrawUnderlying = new uint[](owners.length);

        for (uint i; i < owners.length; ++i) {
            address _user = owners[i];
            state.userBalanceMetaVaultTokens[i] = metaVault_.balanceOf(_user);
            state.userBalanceUnderlying[i] = IERC20(strategy_.underlying()).balanceOf(_user);
            state.userBalanceRecoveryToken[i] = IERC20(metaVault_.recoveryToken(strategy_.vault())).balanceOf(_user);
            state.maxWithdrawUnderlying[i] = metaVault_.maxWithdrawUnderlying(strategy_.vault(), _user);

            state.userBalanceMetaVaultTokensTotal += state.userBalanceMetaVaultTokens[i];
            state.userBalanceUnderlyingTotal += state.userBalanceUnderlying[i];
            state.userBalanceRecoveryTokenTotal += state.userBalanceRecoveryToken[i];
            state.maxWithdrawUnderlyingTotal += state.maxWithdrawUnderlying[i];
        }

        state.metaVaultBalanceUnderlying = IERC20(strategy_.underlying()).balanceOf(address(metaVault_));

        return state;
    }

    function _getArraysForMetaUSD(
        IMetaVault metaVault_,
        IStrategy strategy_
    ) internal view returns (ArraysForMetaVault memory ret, MultiState memory stateBefore) {
        uint count = LARGEST_META_USD_HOLDERS.length;
        ret.owners = new address[](count);
        ret.amounts = new uint[](count);
        ret.expectedUnderlying = new uint[](count);
        ret.minAmountsOut = new uint[](count);
        ret.paused = new bool[](count);

        for (uint i = 0; i < count; ++i) {
            ret.owners[i] = LARGEST_META_USD_HOLDERS[i];
            ret.amounts[i] = 0;
        }

        stateBefore =
            _getMetaVaultMultiState(metaVault_, strategy_, ret.owners, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD);

        for (uint i = 0; i < count; ++i) {
            ret.expectedUnderlying[i] =
                _getExpectedUnderlying(strategy_, metaVault_, stateBefore.maxWithdrawUnderlying[i]);
            ret.minAmountsOut[i] = ret.expectedUnderlying[i] - 1;
            ret.paused[i] = i % 2 == 0; // every second user is paused
        }

        return (ret, stateBefore);
    }

    function _getArraysForWrapped(
        WrappedMetaVault _wrappedMetaVault,
        IVault vault_,
        uint count,
        bool useAllBalance
    ) internal view returns (ArraysForWrapped memory ret, MultiState memory stateBefore) {
        ret.owners = new address[](count);
        ret.shares = new uint[](count);
        ret.expectedUnderlying = new uint[](count);
        ret.minAmountsOut = new uint[](count);
        ret.paused = new bool[](count);

        IMetaVault _metaVault = IMetaVault(_wrappedMetaVault.metaVault());
        (uint priceMetaVaultToken,) = _metaVault.price();

        (uint wrappedPrice,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(address(_wrappedMetaVault));
        for (uint i = 0; i < count; ++i) {
            ret.owners[i] = LARGEST_WRAPPED_META_USD_HOLDERS[i];
            ret.shares[i] = useAllBalance
                ? 0
                : Math.mulDiv(
                    _metaVault.maxWithdrawUnderlying(address(vault_), address(_wrappedMetaVault)) * 999 / 1000,
                    priceMetaVaultToken,
                    wrappedPrice,
                    Math.Rounding.Floor
                ); // wrapped shares = meta vault tokens * price of meta vault token / price of wrapped
            ret.paused[i] = i % 2 == 0; // every second user is paused
        }

        {
            stateBefore = _getMetaVaultMultiState(
                _metaVault, vault_.strategy(), ret.owners, SonicConstantsLib.WRAPPED_METAVAULT_METAUSD
            );

            for (uint i = 0; i < count; ++i) {
                uint shares = (useAllBalance ? _wrappedMetaVault.balanceOf(ret.owners[i]) : ret.shares[i] - 1);
                ret.expectedUnderlying[i] =
                    _getExpectedUnderlying(vault_.strategy(), _metaVault, shares * wrappedPrice / 1e18);
                ret.minAmountsOut[i] = ret.expectedUnderlying[i] - 1;
            }
        }

        return (ret, stateBefore);
    }

    function _getWrappedState(
        IVault vault2,
        IWrappedMetaVault wrapped
    ) internal view returns (WrappedState memory state) {
        WrappedState memory v;
        address recoveryTokenWrapped = wrapped.recoveryToken(vault2.strategy().vault());

        v.totalSupply = wrapped.totalSupply();
        v.totalAssets = wrapped.totalAssets();
        v.totalSupplyRecoveryToken = IERC20(recoveryTokenWrapped).totalSupply();
        (v.wrappedPrice,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(address(wrapped));

        v.userBalanceUnderlying = new uint[](LARGEST_WRAPPED_META_USD_HOLDERS.length);
        v.userBalancesWrapped = new uint[](LARGEST_WRAPPED_META_USD_HOLDERS.length);
        v.userBalanceRecoveryToken = new uint[](LARGEST_WRAPPED_META_USD_HOLDERS.length);
        for (uint i = 0; i < LARGEST_WRAPPED_META_USD_HOLDERS.length; ++i) {
            v.userBalanceUnderlying[i] =
                IERC20(vault2.strategy().underlying()).balanceOf(LARGEST_WRAPPED_META_USD_HOLDERS[i]);
            v.userBalancesWrapped[i] = wrapped.balanceOf(LARGEST_WRAPPED_META_USD_HOLDERS[i]);
            v.userBalanceRecoveryToken[i] = IERC20(recoveryTokenWrapped).balanceOf(LARGEST_WRAPPED_META_USD_HOLDERS[i]);
        }

        v.strategyBalanceUnderlying = IERC20(vault2.strategy().underlying()).balanceOf(address(vault2.strategy()));
        v.wrappedBalanceUnderlying = IERC20(vault2.strategy().underlying()).balanceOf(address(wrapped));

        for (uint i = 0; i < LARGEST_WRAPPED_META_USD_HOLDERS.length; ++i) {
            v.totalShares += wrapped.balanceOf(LARGEST_WRAPPED_META_USD_HOLDERS[i]);
        }
        //        console.log("totalSupply", v.totalSupply);
        //        console.log("totalAssets", v.totalAssets);
        //        console.log("wrappedPrice", v.wrappedPrice);
        //        console.log("totalShares", v.totalShares);
        //        console.log("totalSupplyRecoveryToken", v.totalSupplyRecoveryToken);

        return v;
    }

    //endregion ---------------------------------------------- States

    //region ---------------------------------------------- Internal
    function _setUpRecoveryTokenMetaUsd(IStabilityVault vault_)
        internal
        returns (address recoveryToken, address recoveryTokenMetaUSDC, address recoveryTokenMetaScUsd)
    {
        // ----------------------------------- set up recovery tokens
        recoveryToken = _createRecoveryToken(SonicConstantsLib.METAVAULT_METAUSD, bytes32(uint(0x1)));
        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSD).setRecoveryToken(address(vault_), address(recoveryToken));

        recoveryTokenMetaUSDC = _createRecoveryToken(SonicConstantsLib.METAVAULT_METAUSDC, bytes32(uint(0x2)));
        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC)
            .setRecoveryToken(address(vault_), address(recoveryTokenMetaUSDC));

        recoveryTokenMetaScUsd = _createRecoveryToken(SonicConstantsLib.METAVAULT_METASCUSD, bytes32(uint(0x3)));
        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METASCUSD)
            .setRecoveryToken(address(vault_), address(recoveryTokenMetaScUsd));

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC).changeWhitelist(SonicConstantsLib.METAVAULT_METAUSD, true);

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METASCUSD).changeWhitelist(SonicConstantsLib.METAVAULT_METASCUSD, true);
    }

    function _setUpRecoveryTokenWrapped(address[2] memory vaults_) internal returns (address[4] memory recoveryTokens) {
        // ----------------------------------- set up recovery tokens
        recoveryTokens[0] = _createRecoveryToken(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, bytes32(uint(0x1)));
        for (uint i = 0; i < vaults_.length; ++i) {
            if (vaults_[i] != address(0)) {
                vm.prank(multisig);
                IMetaVault(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD)
                    .setRecoveryToken(vaults_[i], address(recoveryTokens[0]));
            }
        }

        recoveryTokens[1] = _createRecoveryToken(SonicConstantsLib.METAVAULT_METAUSD, bytes32(uint(0x2)));
        for (uint i = 0; i < vaults_.length; ++i) {
            if (vaults_[i] != address(0)) {
                vm.prank(multisig);
                IMetaVault(SonicConstantsLib.METAVAULT_METAUSD).setRecoveryToken(vaults_[i], address(recoveryTokens[1]));
            }
        }

        recoveryTokens[2] = _createRecoveryToken(SonicConstantsLib.METAVAULT_METAUSDC, bytes32(uint(0x3)));
        for (uint i = 0; i < vaults_.length; ++i) {
            if (vaults_[i] != address(0)) {
                vm.prank(multisig);
                IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC)
                    .setRecoveryToken(vaults_[i], address(recoveryTokens[2]));
            }
        }

        recoveryTokens[3] = _createRecoveryToken(SonicConstantsLib.METAVAULT_METASCUSD, bytes32(uint(0x4)));
        for (uint i = 0; i < vaults_.length; ++i) {
            if (vaults_[i] != address(0)) {
                vm.prank(multisig);
                IMetaVault(SonicConstantsLib.METAVAULT_METASCUSD)
                    .setRecoveryToken(vaults_[i], address(recoveryTokens[3]));
            }
        }

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSD)
            .changeWhitelist(SonicConstantsLib.WRAPPED_METAVAULT_METAUSD, true);

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC).changeWhitelist(SonicConstantsLib.METAVAULT_METAUSD, true);

        vm.prank(multisig);
        IMetaVault(SonicConstantsLib.METAVAULT_METASCUSD).changeWhitelist(SonicConstantsLib.METAVAULT_METASCUSD, true);

        return recoveryTokens;
    }

    function _getExpectedUnderlying(
        IStrategy strategy,
        IMetaVault metaVault_,
        uint amountToWithdraw
    ) internal view returns (uint) {
        (uint priceAsset,) = IPriceReader(IPlatform(PLATFORM).priceReader())
            .getPrice(IAToken(strategy.underlying()).UNDERLYING_ASSET_ADDRESS());
        (uint priceMetaVault,) = metaVault_.price();

        // Assume here that AToken to asset is 1:1
        return amountToWithdraw * priceMetaVault / priceAsset * 10 ** IERC20Metadata(strategy.underlying()).decimals() // decimals of the underlying asset
            / 1e18;
    }

    function _prepareSubVaultToWithdraw(
        address metaVault_,
        address subVault_
    ) internal returns (IMetaVault subMetaVault, IStabilityVault vault) {
        subMetaVault = IMetaVault(metaVault_);
        {
            uint vaultIndex = _getVaultIndex(subMetaVault, subVault_);
            _setProportionsForWithdraw(subMetaVault, vaultIndex, vaultIndex == 0 ? 1 : 0);
        }
        vault = IStabilityVault(subMetaVault.vaultForWithdraw());

        assertEq(metaVault.vaultForWithdraw(), metaVault_, "Metavault for withdraw should be the expected one");
        assertEq(address(vault), subVault_, "Subvault for withdraw should be the expected one");
    }

    function _prepareSubVaultToDeposit(
        address metaVault_,
        address subVault_
    ) internal returns (IMetaVault subMetaVault, IStabilityVault vault) {
        subMetaVault = IMetaVault(metaVault_);
        {
            uint vaultIndex = _getVaultIndex(subMetaVault, subVault_);
            _setProportionsForDeposit(subMetaVault, vaultIndex, vaultIndex == 0 ? 1 : 0);
        }
        vault = IStabilityVault(subMetaVault.vaultForDeposit());

        assertEq(metaVault.vaultForWithdraw(), metaVault_, "Metavault for deposit should be the expected one");
        assertEq(address(vault), subVault_, "Subvault for deposit should be the expected one");
    }

    function _getVaultIndex(IMetaVault metaVault_, address vault_) internal view returns (uint) {
        address[] memory vaults = metaVault_.vaults();
        for (uint i = 0; i < vaults.length; ++i) {
            if (vaults[i] == vault_) {
                return i;
            }
        }
        revert(string(abi.encodePacked("Vault not found: ", Strings.toHexString(uint160(vault_), 20))));
    }

    function _setProportionsForWithdraw(IMetaVault metaVault_, uint targetIndex, uint fromIndex) internal {
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

    function _setProportionsForDeposit(IMetaVault metaVault_, uint targetIndex, uint fromIndex) internal {
        uint total = 0;
        uint[] memory props = metaVault_.currentProportions();
        for (uint i = 0; i < props.length; ++i) {
            if (i != targetIndex && i != fromIndex) {
                total += props[i];
            }
        }

        props[fromIndex] = 1e16;
        props[targetIndex] = 1e18 - total - 1e16;

        vm.prank(multisig);
        metaVault_.setTargetProportions(props);

        // _showProportions(metaVault_);
        // console.log(metaVault_.vaultForDeposit(), metaVault_.vaultForWithdraw());
    }

    function _showProportions(IMetaVault metaVault_) internal view {
        address[] memory vaults = metaVault_.vaults();
        uint[] memory props = metaVault_.targetProportions();
        uint[] memory current = metaVault_.currentProportions();
        for (uint i; i < current.length; ++i) {
            console.log("i, current, target", vaults[i], current[i], props[i]);
        }
    }

    function _createRecoveryToken(address metaVault_, bytes32 salt) internal returns (address _recoveryToken) {
        vm.prank(multisig);
        _recoveryToken = metaVaultFactory.deployRecoveryToken(salt, metaVault_);

        assertEq(IRecoveryToken(_recoveryToken).target(), metaVault_, "recovery token target should be metaVault_");
        return _recoveryToken;
    }

    //endregion ---------------------------------------------- Internal

    //region ---------------------------------------------- Helpers
    function _upgradeMetaVault(address metaVault_) internal {
        address vaultImplementation = address(new MetaVault());
        vm.prank(multisig);
        metaVaultFactory.setMetaVaultImplementation(vaultImplementation);
        address[] memory metaProxies = new address[](1);
        metaProxies[0] = address(metaVault_);
        vm.prank(multisig);
        metaVaultFactory.upgradeMetaProxies(metaProxies);
    }

    function _upgradeAmfStrategy(address strategy_) public {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        // deploy new impl and upgrade
        address strategyImplementation = address(new AaveMerklFarmStrategy());
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.AAVE_MERKL_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(strategy_);
    }

    function _upgradeSiloStrategy(address strategy_) public {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        // deploy new impl and upgrade
        address strategyImplementation = address(new SiloStrategy());
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.SILO, strategyImplementation);

        factory.upgradeStrategyProxy(strategy_);
    }

    function _upgradeCVault(address cVault_) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        // deploy new impl and upgrade
        address vaultImplementation = address(new CVault());
        vm.prank(multisig);
        factory.setVaultImplementation(VaultTypeLib.COMPOUNDING, vaultImplementation);
        factory.upgradeVaultProxy(address(cVault_));
    }

    function _upgradeWrappedMetaVault() internal {
        address newWrapperImplementation = address(new WrappedMetaVault());
        vm.startPrank(multisig);
        metaVaultFactory.setWrappedMetaVaultImplementation(newWrapperImplementation);
        address[] memory proxies = new address[](2);
        proxies[0] = SonicConstantsLib.WRAPPED_METAVAULT_METAS;
        proxies[1] = SonicConstantsLib.WRAPPED_METAVAULT_METAUSD;
        metaVaultFactory.upgradeMetaProxies(proxies);
        vm.stopPrank();
    }

    function _upgradePlatform() internal {
        metaVaultFactory = IMetaVaultFactory(SonicConstantsLib.METAVAULT_FACTORY);

        address[] memory proxies = new address[](1);
        proxies[0] = address(metaVaultFactory);

        address[] memory implementations = new address[](1);
        implementations[0] = address(new MetaVaultFactory());

        vm.prank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.08.0-alpha", proxies, implementations);

        skip(1 days);

        vm.prank(multisig);
        IPlatform(PLATFORM).upgrade();
    }

    function _setupMetaVaultFactory() internal {
        address recoveryTokenImplementation = address(new RecoveryToken());
        vm.prank(multisig);
        metaVaultFactory.setRecoveryTokenImplementation(recoveryTokenImplementation);
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
    //endregion ---------------------------------------------- Helpers
}
