// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console, Test, Vm} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626, IERC20} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {MetaVault, IMetaVault, IStabilityVault} from "../../src/core/vaults/MetaVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";

/// @dev Upgrade MetaVault after fixing the issues found in the audit
contract MetaVaultSonicUpgradeAudit is Test {
    // uint public constant FORK_BLOCK = 31972376; // Jun-05-2025 06:49:31 AM +UTC
    uint public constant FORK_BLOCK = 33291167; // Jun-11-2025 07:08:05 AM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVault public metaVault;
    IMetaVaultFactory public metaVaultFactory;
    address public multisig;
    IPriceReader public priceReader;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(33291167); // Jun-11-2025 07:08:05 AM +UTC

        metaVault = IMetaVault(SonicConstantsLib.METAVAULT_metaUSD);
        metaVaultFactory = IMetaVaultFactory(IPlatform(PLATFORM).metaVaultFactory());
        multisig = IPlatform(PLATFORM).multisig();

        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
    }

    /// @notice #303: Fix slippage check in meta vault, 3.1.3 in audit report
    function testMetaVaultIssue303() public {
        _upgradeMetaVault(address(metaVault));

        address[] memory assets = metaVault.assetsForDeposit();
        uint[] memory depositAmounts = _getAmountsForDeposit(1000, assets);
        _dealAndApprove(address(this), address(metaVault), assets, depositAmounts);

        // block 31972376, Jun-05-2025 06:49:31 AM +UTC

        //        targetVaultPrice 999724000000000000
        //        targetVaultSharesAfter 3364078307853266063192
        //        amountsMax 1000276076
        //        depositedTvl 999999999576624071218
        //        balanceOut 999999999576624071218
        //        sharesToCreate 999038573804442028789

        // ----------- get values of sharesToCreate
        uint snapshotId = 0;
        uint balanceOut = 0;
        uint sharesToCreate = 999038573804442028789; // preview deposit returns 999038561981127327318

        if (FORK_BLOCK != 31972376) {
            // we can take sharesToCreate from ExceedSlippage
            // but before fix there was balanceOut value there
            // so upgrade test will work on 31972376 only
            // after upgrade it will work in assumption that sharesToCreate is used for slippage check
            snapshotId = vm.snapshotState();

            bytes memory returnData = new bytes(0);

            try metaVault.depositAssets(
                assets,
                depositAmounts,
                type(uint).max, // revert ExceedSlippage
                address(this)
            ) {} catch (bytes memory reason) {
                returnData = reason;
            }

            bytes4 selector = bytes4(returnData);
            require(selector == IStabilityVault.ExceedSlippage.selector, "Not ExceedSlippage");

            bytes memory errorData = new bytes(returnData.length - 4);
            for (uint i = 0; i < errorData.length; ++i) {
                errorData[i] = returnData[i + 4];
            }

            (sharesToCreate,) = abi.decode(errorData, (uint, uint));
            vm.revertToState(snapshotId);
        }

        // ----------- get values of balanceOut
        snapshotId = vm.snapshotState();
        vm.recordLogs();
        metaVault.depositAssets(
            assets,
            depositAmounts,
            0, // no revert
            address(this)
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 depositAssetsSignature = keccak256("DepositAssets(address,address[],uint256[],uint256)");
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == depositAssetsSignature) {
                (,, balanceOut) = abi.decode(logs[i].data, (address[], uint[], uint));
                break;
            }
        }
        vm.revertToState(snapshotId);

        assertNotEq(sharesToCreate, 0, "sharesToCreate should not be zero");
        assertNotEq(balanceOut, 0, "balanceOut should not be zero");
        assertNotEq(sharesToCreate, balanceOut, "balanceOut is used for slippage check??");

        // ----------- ensure that sharesToCreate is used to slippage check
        vm.expectRevert();
        metaVault.depositAssets(
            assets,
            depositAmounts,
            sharesToCreate + 1, // revert
            address(this)
        );
        vm.roll(block.number + 6);

        snapshotId = vm.snapshotState();
        metaVault.depositAssets(
            assets,
            depositAmounts,
            sharesToCreate, // no revert
            address(this)
        );
        vm.revertToState(snapshotId);

        if (balanceOut < sharesToCreate) {
            metaVault.depositAssets(
                assets,
                depositAmounts,
                balanceOut + 1, // no revert
                address(this)
            );
        }
    }

    /// @notice #308: Test to reproduce issue #308 before changes, 3.1.5 in audit report
    function testMetaVaultReproduce308() public {
        if (block.number == 31972376) {
            address user = makeAddr("user");
            address subMetaVault = metaVault.vaultForDeposit();

            // ----- Deposit asset on balance of meta vault to simulate situation when meta vault has some assets on balance
            address[] memory assets = metaVault.assetsForDeposit();
            uint[] memory depositAmounts = _getAmountsForDeposit(100, assets);
            _dealAndApprove(subMetaVault, address(1), assets, depositAmounts); // we don't need dealing

            // --------------------- Assume that metavaults give approve to subvaults for required assets
            vm.prank(address(metaVault));
            IERC20(assets[0]).approve(subMetaVault, type(uint).max);

            address cvault = IMetaVault(subMetaVault).vaultForDeposit();
            vm.prank(address(subMetaVault));
            IERC20(assets[0]).approve(cvault, type(uint).max);

            // --------------------- Prepare fake asset
            uint[] memory fakeAmounts = new uint[](1);
            fakeAmounts[0] = 100e6;
            address[] memory fakeAssets = new address[](1);
            fakeAssets[0] = SonicConstantsLib.TOKEN_SACRA;
            _dealAndApprove(user, address(metaVault), fakeAssets, fakeAmounts);

            // --------------------- Deposit fake asset
            uint maxWithdrawBefore = metaVault.balanceOf(user);

            vm.prank(user);
            metaVault.depositAssets(fakeAssets, fakeAmounts, 0, user);
            uint maxWithdrawAfter = metaVault.balanceOf(user);

            assertEq(IERC20(fakeAssets[0]).balanceOf(user), fakeAmounts[0], "Balance of the fake asset wasn't changed");
            assertGt(maxWithdrawAfter, maxWithdrawBefore, "User got some shares");
        }
    }

    /// @notice #308: Prevent manipulation with input assets in meta vault, 3.1.5 in audit report
    function testMetaVaultUpgrade308() public {
        address user = makeAddr("user");
        address subMetaVault = metaVault.vaultForDeposit();
        address cvault = IMetaVault(subMetaVault).vaultForDeposit();

        // --------------------- Upgrade MetaVault to the new implementation
        _upgradeMetaVault(address(metaVault));
        _upgradeSubVaults(true);

        // --------------------- Prepare metaVault to the state suitable for malicious deposit
        {
            // Deposit asset on balance of meta vault to simulate situation when meta vault has some assets on balance
            address[] memory assets = metaVault.assetsForDeposit();
            uint[] memory depositAmounts = _getAmountsForDeposit(100, assets);
            _dealAndApprove(subMetaVault, address(1), assets, depositAmounts); // we don't need dealing
            assertEq(assets.length, 1);

            // --------------------- Assume that metavaults give approve to subvaults for required assets
            vm.prank(address(metaVault));
            IERC20(assets[0]).approve(subMetaVault, type(uint).max);

            vm.prank(address(subMetaVault));
            IERC20(assets[0]).approve(cvault, type(uint).max);
        }

        // --------------------- Fail to deposit fake asset
        {
            uint[] memory fakeAmounts = new uint[](1);
            fakeAmounts[0] = 100e6;
            address[] memory fakeAssets = new address[](1);
            fakeAssets[0] = SonicConstantsLib.TOKEN_SACRA;
            _dealAndApprove(user, address(metaVault), fakeAssets, fakeAmounts);

            vm.expectRevert(); // MetaVault: assets for deposit should be the same as assets for sub-metaVault
            vm.prank(user);
            metaVault.depositAssets(fakeAssets, fakeAmounts, 0, user);
        }

        // --------------------- Fail to deposit too many assets
        {
            address[] memory assets = metaVault.assets();
            assertEq(assets.length, 2, "metavault has 2 sub-metavaults with different assets");

            uint[] memory depositAmounts = new uint[](2);
            depositAmounts[0] = 100e6; // scUSD
            depositAmounts[1] = 100e6; // scEUR

            _dealAndApprove(user, address(metaVault), assets, depositAmounts);

            vm.expectRevert(); // user should provide assets for single sub-metaVault only
            vm.prank(user);
            metaVault.depositAssets(assets, depositAmounts, 0, user);
        }
    }

    /// @notice #321: New depositor in metVault can deposit right before hardwork and grab rewards that don't belong to him
    function testMetaVaultReproduce321() public {
        address victim = address(1);
        address hacker = address(2);
        // ---------------------- Allow hardwork on deposit in all subvaults
        _enableHardworkOnDeposit();

        // ---------------------- Victim deposits huge amount of assets and waits long time to get rewards
        address[] memory assets = metaVault.assetsForDeposit();
        uint[] memory depositAmounts = _getAmountsForDeposit(1e6, assets);
        _dealAndApprove(victim, address(metaVault), assets, depositAmounts);
        vm.prank(victim);
        metaVault.depositAssets(assets, depositAmounts, 0, victim);
        uint maxWithdraw0 = metaVault.balanceOf(victim);
        console.log("maxWithdraw0", maxWithdraw0);

        vm.roll(block.number + 10_000); // wait some time to get rewards

        // ---------------------- Get real maxWithdraw amount
        uint snapshotId = vm.snapshotState();
        _doHardworkAllVaults();
        uint maxWithdraw = metaVault.balanceOf(victim);
        console.log("maxWithdraw", maxWithdraw);
        console.log("Victim potential profit:", maxWithdraw - maxWithdraw0);
        vm.revertToState(snapshotId);

        // ---------------------- Hacker enters just before hardwork
        assets = metaVault.assetsForDeposit();
        depositAmounts = _getAmountsForDeposit(1000, assets);
        vm.prank(hacker);
        metaVault.depositAssets(assets, depositAmounts, 0, victim);

        _doHardworkAllVaults();

        uint maxWithdraw2 = metaVault.balanceOf(victim);
        uint maxWithdraw3 = metaVault.balanceOf(hacker);
        console.log("maxWithdraw2", maxWithdraw2);
        console.log("maxWithdraw3", maxWithdraw3);
        console.log("Victim profit:", maxWithdraw2 - 1e6);
        console.log("Hacker profit:", maxWithdraw3 - 1e3);
    }

    //region ------------------------------ Auxiliary Functions
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

    function _getAmountsForDeposit(
        uint usdValue,
        address[] memory assets
    ) internal view returns (uint[] memory depositAmounts) {
        depositAmounts = new uint[](assets.length);
        for (uint j; j < assets.length; ++j) {
            (uint price,) = priceReader.getPrice(assets[j]);
            require(price > 0, "UniversalTest: price is zero. Forget to add swapper routes?");
            depositAmounts[j] = usdValue * 10 ** IERC20Metadata(assets[j]).decimals() * 1e18 / price;
        }
    }

    function _dealAndApprove(
        address user,
        address metavault,
        address[] memory assets,
        uint[] memory amounts
    ) internal {
        for (uint j; j < assets.length; ++j) {
            deal(assets[j], user, amounts[j]);
            vm.prank(user);
            IERC20(assets[j]).approve(metavault, amounts[j]);
        }
    }

    function _upgradeSubVaults(bool updateCVaults) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        address[] memory vaults0 = IMetaVault(address(metaVault)).vaults();

        for (uint i = 0; i < vaults0.length; i++) {
            _upgradeMetaVault(vaults0[i]);

            if (updateCVaults) {
                address[] memory vaults = IMetaVault(address(vaults0[i])).vaults();
                for (uint j = 0; j < vaults.length; j++) {
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
                    vm.prank(multisig);
                    factory.upgradeVaultProxy(vaults[j]);

                    vm.prank(multisig);
                    IStabilityVault(vaults[j]).setLastBlockDefenseDisabled(true);
                }
            }
        }
    }

    function _enableHardworkOnDeposit() internal {
        address[] memory vaults0 = IMetaVault(address(metaVault)).vaults();
        for (uint i = 0; i < vaults0.length; i++) {
            address[] memory vaults = IMetaVault(address(vaults0[i])).vaults();
            for (uint j = 0; j < vaults.length; j++) {
                vm.prank(multisig);
                IVault(vaults[j]).setDoHardWorkOnDeposit(true);
            }
        }
    }

    function _doHardworkAllVaults() internal {
        address[] memory vaults0 = IMetaVault(address(metaVault)).vaults();
        for (uint i = 0; i < vaults0.length; i++) {
            address[] memory vaults = IMetaVault(address(vaults0[i])).vaults();
            for (uint j = 0; j < vaults.length; j++) {
                vm.prank(multisig);
                IVault(vaults[j]).doHardWork();
            }
        }
    }
    //endregion ------------------------------ Auxiliary Functions
}
