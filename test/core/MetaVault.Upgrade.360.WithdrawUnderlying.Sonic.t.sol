// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console, Test} from "forge-std/Test.sol";
import {IERC4626, IERC20} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IAToken} from "../../src/integrations/aave/IAToken.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AaveMerklFarmStrategy} from "../../src/strategies/AaveMerklFarmStrategy.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {SiloManagedFarmStrategy} from "../../src/strategies/SiloManagedFarmStrategy.sol";
import {SiloStrategy} from "../../src/strategies/SiloStrategy.sol";

/// #360 - withdraw underlying from MetaVaults
contract MetaVault360WithdrawUnderlyingSonicUpgrade is Test {
    // uint public constant FORK_BLOCK = 40824190; // Jul-30-2025 02:39:35 AM +UTC (before the hack of 04 aug 2025)
    uint public constant FORK_BLOCK = 41962444; // Aug-07-2025 05:43:49 AM +UTC

    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public multisig;
    IMetaVault public metaVault;
    IMetaVaultFactory public metaVaultFactory;

    address internal user;
    address internal user2;

    address[17] internal LARGEST_META_USD_HOLDERS;

    constructor() {
        user = makeAddr("user");
        user2 = makeAddr("user2");

        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        multisig = IPlatform(PLATFORM).multisig();
        metaVaultFactory = IMetaVaultFactory(SonicConstantsLib.METAVAULT_FACTORY);
        metaVault = IMetaVault(SonicConstantsLib.METAVAULT_metaUSD);

        _upgradeMetaVault(address(metaVault));

        // all holders with balances > 1000 metaUSD except wrapped metaUSD
        LARGEST_META_USD_HOLDERS = [
            0x8901D9cf0272A2876525ee25Fcbb9E423c4B95f6,
            0x59603A3AB3e33F07A2B9a4419399d502a1Fb6a95,
            0xb1E615255CC8DD83F2AB9E332c1624b0A6B3Ad80,
            0xc2d5904602e2d76D3D04EC28A5A1c52E136C4475,
            0xf29593aC58C78ECC0bF1d0e8B55E819c5B521aE4,
            0xCE785cccAa0c163E6f83b381eBD608F98f694C44,
            0x97006dB48f27A1312BbeD5E96dE146A97A78E396,
            0x34F6eA796d06870db4dD5775D9e665539Bc6bBA0,
            0xa9714f7291251Bc1b0D0dBA6481959Ef814E171a,
            0xd63295C755F84FCd57663Ea2e2f9E6fee1830139,
            0x8C9C2f167792254C651FcA36CA40Ed9a229e5921,
            0xaC207c599e4A07F9A8cc5E9cf49B02E20AB7ba69,
            0x288a2395f027F65684D836754bA43Afa20CA09e6,
            0x5027457c50A3b45772baFE70e2E6f05D98514ad4,
            0xec8e3A07d6c5c172e821588EF1749b739A06b20E,
            0xaBf0f7bD0Dc8Ce44b084B4B66b8Db97F1b9Ce419,
            0xdF5e92e18c282B61b509Fb3223BaC6c4d0C8dEE6
        ];
    }

//    /// @notice Withdraw underlying from the given AMF-subvault
//    function testWithdrawFromSubvaultDirectlyAMF() public {
//        vm.prank(multisig);
//        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaUSDC);
//
//        (, IStabilityVault vault) = _prepareSubVaultToWithdraw(
//            SonicConstantsLib.METAVAULT_metaUSDC, SonicConstantsLib.VAULT_C_Credix_USDC_AMFa0
//        );
//        _upgradeAmfStrategy(address(IVault(SonicConstantsLib.VAULT_C_Credix_USDC_AMFa0).strategy()));
//
//        // ----------------------------------- detect underlying and amount to withdraw
//        IStrategy strategy = IVault(address(vault)).strategy();
//
//        vm.prank(multisig);
//        AaveMerklFarmStrategy(address(strategy)).setUnderlying();
//
//        assertNotEq(strategy.underlying(), address(0), "Underlying should not be zero address");
//
//        // ----------------------------------- withdraw underlying from the given vault
//        address[] memory assets = new address[](1);
//        assets[0] = strategy.underlying();
//
//        address holder = SonicConstantsLib.METAVAULT_metaUSDC;
//        uint expectedUnderlying = Math.mulDiv(
//            vault.balanceOf(holder),
//            strategy.total(),
//            vault.totalSupply(),
//            Math.Rounding.Ceil
//        );
//
//        uint balanceUnderlyingBefore = IERC20(assets[0]).balanceOf(holder);
//        uint amountToWithdraw = vault.maxWithdraw(holder);
//
//        vm.prank(holder);
//        vault.withdrawAssets(assets, amountToWithdraw, new uint[](1));
//
//        uint balanceUnderlyingAfter = IERC20(assets[0]).balanceOf(holder);
//
//        assertEq(
//            balanceUnderlyingAfter - balanceUnderlyingBefore, expectedUnderlying, "Withdrawn amount should match expected value"
//        );
//    }
//
//    function testWithdrawFromChildMetavaultAMF() public {
//        vm.prank(multisig);
//        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaUSDC);
//
//        address holder = SonicConstantsLib.METAVAULT_metaUSD;
//        (IMetaVault subMetaVault, IStabilityVault vault) = _prepareSubVaultToWithdraw(
//            SonicConstantsLib.METAVAULT_metaUSDC,
//            SonicConstantsLib.VAULT_C_Credix_USDC_AMFa0
//        );
//        _upgradeAmfStrategy(address(IVault(SonicConstantsLib.VAULT_C_Credix_USDC_AMFa0).strategy()));
//        _upgradeCVault(SonicConstantsLib.VAULT_C_Credix_USDC_AMFa0);
//
//        // ----------------------------------- detect underlying and amount to withdraw
//        IStrategy strategy = IVault(address(vault)).strategy();
//
//        vm.prank(multisig);
//        AaveMerklFarmStrategy(address(strategy)).setUnderlying();
//
//        assertNotEq(strategy.underlying(), address(0), "AMF: Underlying should not be zero address 1");
//
//        // ----------------------------------- withdraw underlying through sub-MetaVault
//        address[] memory assets = new address[](1);
//        assets[0] = strategy.underlying();
//
//        uint amountToWithdraw = subMetaVault.maxWithdrawUnderlying(address(vault), holder);
//        (uint priceAsset,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(IAToken(assets[0]).UNDERLYING_ASSET_ADDRESS());
//        (uint priceMetaVault,) = subMetaVault.price();
//        // Assume here that AToken to asset is 1:1
//        uint expectedUnderlying = amountToWithdraw * priceMetaVault
//            / priceAsset
//            * 10 ** IERC20Metadata(assets[0]).decimals() // decimals of the underlying asset
//            / 1e18;
//        uint balanceUnderlyingBefore = IERC20(assets[0]).balanceOf(holder);
//
//        vm.prank(holder);
//        MetaVault(address(subMetaVault)).withdrawUnderlying(address(vault), amountToWithdraw, 0, holder, holder);
//
//        uint balanceUnderlyingAfter = IERC20(assets[0]).balanceOf(holder);
//
//        assertApproxEqAbs(
//            balanceUnderlyingAfter - balanceUnderlyingBefore,
//            expectedUnderlying,
//            1,
//            "AMF: Withdrawn amount should match expected value 1"
//        );
//    }

    function testDepositWithdrawUnderlyingFromChildMetavaultAMF() public {
        vm.prank(multisig);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaUSDC);

        (IMetaVault subMetaVault, IStabilityVault vault) = _prepareSubVaultToDeposit(
            SonicConstantsLib.METAVAULT_metaUSDC,
            SonicConstantsLib.VAULT_C_Credix_USDC_AMFa0
        );
        _upgradeAmfStrategy(address(IVault(SonicConstantsLib.VAULT_C_Credix_USDC_AMFa0).strategy()));
        _upgradeCVault(SonicConstantsLib.VAULT_C_Credix_USDC_AMFa0);

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
        uint expectedUnderlying =_getExpectedUnderlying(strategy, subMetaVault, amountToWithdraw);
        uint balanceUnderlyingBefore = IERC20(assets[0]).balanceOf(user);

        vm.prank(user);
        MetaVault(address(subMetaVault)).withdrawUnderlying(address(vault), amountToWithdraw, 0, user, user);
        console.log("amountToWithdraw", amountToWithdraw);

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

    function testDepositWithdrawUnderlyingFromMetaUsdAMF() public {
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaUSD);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaUSDC);

        IMetaVault _metaVault = IMetaVault(SonicConstantsLib.METAVAULT_metaUSD);

        (, IStabilityVault vault) = _prepareSubVaultToDeposit(
            SonicConstantsLib.METAVAULT_metaUSDC,
            SonicConstantsLib.VAULT_C_Credix_USDC_AMFa0
        );
        _upgradeAmfStrategy(address(IVault(SonicConstantsLib.VAULT_C_Credix_USDC_AMFa0).strategy()));
        _upgradeCVault(SonicConstantsLib.VAULT_C_Credix_USDC_AMFa0);

        // ----------------------------------- detect underlying and amount to withdraw
        IStrategy strategy = IVault(address(vault)).strategy();

        vm.prank(multisig);
        AaveMerklFarmStrategy(address(strategy)).setUnderlying();

        assertNotEq(strategy.underlying(), address(0), "AMF: Underlying should not be zero address 3");

        // ----------------------------------- deposit assets into the given vault
        address[] memory assets = _metaVault.assetsForDeposit();
        uint[] memory amounts = new uint[](1);
        amounts[0] = 1000e6;

        uint underlyingStrategyBalanceBeforeDeposit = IERC20(strategy.underlying()).balanceOf(address(strategy));

        deal(assets[0], user, amounts[0]);

        vm.prank(user);
        IERC20(assets[0]).approve(address(_metaVault), amounts[0]);

        vm.prank(user);
        _metaVault.depositAssets(assets, amounts, 0, user);
        vm.roll(block.number + 6);

        uint underlyingStrategyBalanceAfterDeposit = IERC20(strategy.underlying()).balanceOf(address(strategy));

        // ----------------------------------- withdraw all underlying
        uint amountToWithdraw = _metaVault.maxWithdrawUnderlying(address(vault), user);
        uint expectedUnderlying =_getExpectedUnderlying(strategy, _metaVault, amountToWithdraw);
        uint balanceUnderlyingBefore = IERC20(strategy.underlying()).balanceOf(user);

        vm.prank(user);
        MetaVault(address(_metaVault)).withdrawUnderlying(address(vault), amountToWithdraw, 0, user, user);

        uint balanceUnderlyingAfter = IERC20(strategy.underlying()).balanceOf(user);

        // ----------------------------------- check results
        assertApproxEqAbs(
            balanceUnderlyingAfter - balanceUnderlyingBefore,
            expectedUnderlying,
            1,
            "AMF: Withdrawn amount should match expected value 3"
        );

        assertEq(
            balanceUnderlyingAfter - balanceUnderlyingBefore,
            underlyingStrategyBalanceAfterDeposit - underlyingStrategyBalanceBeforeDeposit,
            "User has withdrawn all deposited underlying 3"
        );

        assertEq(
            balanceUnderlyingAfter - balanceUnderlyingBefore,
            1000e6,
            "User has withdrawn amount of atokens same to the deposited amount 3"
        );

        assertApproxEqAbs(_metaVault.balanceOf(user), 0, 1e6, "User should have no shares left after withdraw 3");
    }

    function testWithdrawUnderlyingMetaUsdc() public {
        // ---------------------------- prepare to deposit
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaUSD);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaUSDC);

        IMetaVault _metaVault = IMetaVault(SonicConstantsLib.METAVAULT_metaUSD);

        (, IStabilityVault vault) = _prepareSubVaultToDeposit(
            SonicConstantsLib.METAVAULT_metaUSDC,
            SonicConstantsLib.VAULT_C_Credix_USDC_AMFa0
        );
        _upgradeAmfStrategy(address(IVault(SonicConstantsLib.VAULT_C_Credix_USDC_AMFa0).strategy()));
        _upgradeCVault(SonicConstantsLib.VAULT_C_Credix_USDC_AMFa0);

        IStrategy strategy = IVault(address(vault)).strategy();

        vm.prank(multisig);
        AaveMerklFarmStrategy(address(strategy)).setUnderlying();

        // --------------------------- prepare to withdraw
        address holder = SonicConstantsLib.WRAPPED_METAVAULT_metaUSD;
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
            uint underlyingOut = MetaVault(address(_metaVault)).withdrawUnderlying(
                address(vault), amountToWithdraw, 0, user2, holder
            );

            assertEq(underlyingOut, IERC20(strategy.underlying()).balanceOf(user2), "Withdrawn amount should be correct");
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

            vm.expectRevert(abi.encodeWithSelector(IMetaVault.VaultNotFound.selector, SonicConstantsLib.VAULT_C_USDC_S_34));
            vm.prank(holder);
            MetaVault(address(_metaVault)).withdrawUnderlying(SonicConstantsLib.VAULT_C_USDC_S_34, 1e18, 0, holder, holder);

            vm.revertToState(snapshot);
        }
    }

    function testWithdrawUnderlyingMetaScUsd() public {
        // ---------------------------- prepare to deposit
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaUSD);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metascUSD);

        IMetaVault _metaVault = IMetaVault(SonicConstantsLib.METAVAULT_metaUSD);
        IStabilityVault vault = IStabilityVault(SonicConstantsLib.VAULT_C_Credix_scUSD_AMFa0);

        _upgradeAmfStrategy(address(IVault(address(vault)).strategy()));
        _upgradeCVault(address(vault));

        IStrategy strategy = IVault(address(vault)).strategy();

        vm.prank(multisig);
        AaveMerklFarmStrategy(address(strategy)).setUnderlying();

        // --------------------------- TooHighAmount
        {
            uint snapshot = vm.snapshotState();

            address holder = SonicConstantsLib.WRAPPED_METAVAULT_metaUSD;
            uint holderBalance = _metaVault.balanceOf(holder);
            uint maxWithdrawUnderlying = _metaVault.maxWithdrawUnderlying(address(vault), holder);
            uint maxWithdraw = _metaVault.maxWithdraw(holder);
            assertLt(maxWithdraw, maxWithdrawUnderlying, "Meta vault doesn't have enough liquidity after credix hack");

            vm.expectRevert(abi.encodeWithSelector(IMetaVault.TooHighAmount.selector));
            vm.prank(holder);
            MetaVault(address(_metaVault)).withdrawUnderlying(address(vault), maxWithdrawUnderlying + 1, 0, holder, holder);

            uint expectedUnderlying =_getExpectedUnderlying(strategy, _metaVault, maxWithdrawUnderlying);

            vm.prank(holder);
            uint withdrawn = MetaVault(address(_metaVault)).withdrawUnderlying(address(vault), maxWithdrawUnderlying, 0, holder, holder);

            assertApproxEqAbs(withdrawn, expectedUnderlying, 1, "Withdrawn amount should match expected value 4");
            assertApproxEqAbs(holderBalance - _metaVault.balanceOf(holder), maxWithdrawUnderlying, 1, "Holder should have correct balance after withdraw 4");


            vm.revertToState(snapshot);
        }
    }

    function testWithdrawUnderlyingEmergency() public {
        // ---------------------------- set up contracts
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaUSD);
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaUSDC);

        IMetaVault _metaVault = IMetaVault(SonicConstantsLib.METAVAULT_metaUSD);
        IVault vault = IVault(SonicConstantsLib.VAULT_C_Credix_USDC_AMFa0);

        _upgradeAmfStrategy(address(vault.strategy()));
        _upgradeCVault(address(vault));

        IStrategy strategy = IVault(address(vault)).strategy();

        vm.prank(multisig);
        AaveMerklFarmStrategy(address(strategy)).setUnderlying();

        // --------------------------- withdraw underlying in emergency
        uint count = 17;
        address[] memory owners = new address[](count);
        uint[] memory amounts = new uint[](count);
        for (uint i = 0; i < count; ++i) {
            owners[i] = LARGEST_META_USD_HOLDERS[i];
            amounts[i] = 0;
        }

        uint gas = gasleft();
        vm.prank(multisig);
        uint[] memory amountsOut = _metaVault.withdrawUnderlyingEmergency(address(vault), owners, amounts);
        console.log("Gas used for withdrawUnderlyingEmergency:", gas - gasleft());
        for (uint i = 0; i < count; ++i) {
            console.log("i, amountOut", i, amountsOut[i]);
        }
    }

    function testWithdrawUnderlyingEmergencyBadPaths() public {
        //---------------------------- try to withdraw by non-multisig

        //---------------------------- try to withdraw from not-broken vault

        // todo
    }

    //region ---------------------------------------------- Internal
    function _getExpectedUnderlying(IStrategy strategy, IMetaVault metaVault_, uint amountToWithdraw) internal view returns (uint) {
        (uint priceAsset,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(
            IAToken(strategy.underlying()).UNDERLYING_ASSET_ADDRESS()
        );
        (uint priceMetaVault,) = metaVault_.price();

        // Assume here that AToken to asset is 1:1
        return amountToWithdraw * priceMetaVault
            / priceAsset
            * 10 ** IERC20Metadata(strategy.underlying()).decimals() // decimals of the underlying asset
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
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.AAVE_MERKL_FARM,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: false,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(strategy_);
    }

    function _upgradeSiloStrategy(address strategy_) public {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        // deploy new impl and upgrade
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

        factory.upgradeStrategyProxy(strategy_);
    }

    function _upgradeCVault(address cVault_) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

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
        factory.upgradeVaultProxy(address(cVault_));
    }
    //endregion ---------------------------------------------- Helpers
}
