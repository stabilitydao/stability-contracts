// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console, Test, Vm} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626, IERC20} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MetaVault, IMetaVault, IStabilityVault} from "../../src/core/vaults/MetaVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";

import {SupportsInterfaceWithLookupMock} from "../../lib/openzeppelin-contracts/contracts/mocks/ERC165/ERC165InterfacesSupported.sol";

/// @dev Upgrade MetaVault after fixing the issues found in the audit
contract MetaVaultSonicUpgradeAudit is Test {
    uint public constant FORK_BLOCK = 31972376; // Jun-05-2025 06:49:31 AM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVault public metaVault;
    IMetaVaultFactory public metaVaultFactory;
    address public multisig;
    IPriceReader public priceReader;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

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

    function testMetaVaultReproduce308() public {
        _upgradeMetaVault(address(metaVault));
        _upgradeSubVaults();

        address user = makeAddr("user");
        address subMetaVault = metaVault.vaultForDeposit();

        // ----- Deposit asset on balance of meta vault to simulate situation when meta vault has some assets on balance
        address[] memory assets = metaVault.assetsForDeposit();
        uint[] memory depositAmounts = _getAmountsForDeposit(100, assets);
        _dealAndApprove(subMetaVault, address(1), assets, depositAmounts); // we don't need dealing


        // --------------------- Assume that metavault give approve to subvault for required assets
        vm.prank(address(metaVault));
        IERC20(assets[0]).approve(subMetaVault, type(uint).max);

        console.log("assets[0]", assets[0]);
        console.log("metavault", address(metaVault));
        console.log("vaultForDeposit", subMetaVault);
        console.log("user", user);
        console.log("sacra", SonicConstantsLib.TOKEN_USDT);

        address cvault = IMetaVault(subMetaVault).vaultForDeposit();
        vm.prank(address(subMetaVault));
        IERC20(assets[0]).approve(cvault, type(uint).max);
        console.log("!!!!!!!allowance", IERC20(0x29219dd400f2Bf60E5a23d13Be72B486D4038894).allowance(subMetaVault, cvault));

        console.log("submetavault", subMetaVault);
        console.log("cvault", cvault);


        // --------------------- Prepare fake asset
        uint[] memory fakeAmounts = new uint[](1);
        fakeAmounts[0] = 100e6;
        address[] memory fakeAssets = new address[](1);
        fakeAssets[0] = SonicConstantsLib.TOKEN_SACRA;
        _dealAndApprove(user, address(metaVault), fakeAssets, fakeAmounts);

        console.log("Fake asset balance before", IERC20(fakeAssets[0]).balanceOf(user));
        console.log("Real asset balance before", IERC20(assets[0]).balanceOf(user));
        console.log("0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE balance before", IERC20(0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE).balanceOf(user));
        console.log("fakeAssets", address(fakeAssets[0]));

        // --------------------- Deposit fake asset
        vm.prank(user);
        metaVault.depositAssets(fakeAssets, fakeAmounts, 0, user);
        console.log("deposited");

        // --------------------- Withdraw and take profit
        vm.prank(user);
        uint maxWithdraw = metaVault.balanceOf(user);
        console.log("maxWithdraw", maxWithdraw);

        vm.roll(block.number + 6);

        vm.prank(user);
        metaVault.withdrawAssets(assets, maxWithdraw, new uint[](1));

        console.log("Fake asset balance after", IERC20(fakeAssets[0]).balanceOf(user));
        console.log("Real asset balance after", IERC20(assets[0]).balanceOf(user), assets[0]);
        console.log("0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE balance after", IERC20(0xd3DCe716f3eF535C5Ff8d041c1A41C3bd89b97aE).balanceOf(user));
    }

    /// @notice #308: Prevent manipulation with input assets in meta vault, 3.1.5 in audit report
    function testMetaVaultUpgrade308() public {
        // --------------------- Upgrade MetaVault to the new implementation
        _upgradeMetaVault(address(metaVault));

        // --------------------- Deposit asset and underlying

        // --------------------- Bad paths: try to deposit two assets at the same time

        // --------------------- Bad paths: try to deposit fake asset
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

    function _upgradeSubVaults() internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        address[] memory vaults0 = IMetaVault(address(metaVault)).vaults();

        for (uint i = 0; i < vaults0.length; i++) {
            _upgradeMetaVault(vaults0[i]);

            address[] memory vaults = IMetaVault(address(vaults0[i])).vaults();
            for (uint i = 0; i < vaults.length; i++) {
                console.log("i", i, vaults[i]);
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
                console.log("i", i);
                vm.prank(multisig);
                factory.upgradeVaultProxy(vaults[i]);
                console.log("i", i);

                vm.startPrank(multisig);
                IStabilityVault(vaults[i]).setLastBlockDefenseDisabled(true);
                vm.stopPrank();
            }
        }
    }
    //endregion ------------------------------ Auxiliary Functions
}
