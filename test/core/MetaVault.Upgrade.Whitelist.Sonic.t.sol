// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console, Test} from "forge-std/Test.sol";
import {IERC4626, IERC20} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MetaVault, IMetaVault, IStabilityVault} from "../../src/core/vaults/MetaVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";

/// @dev Add whitelist and setLastBlockDefenseDisabledTx into MetaVault
contract MetaVaultSonicUpgradeWhitelist is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVault public metaVault;
    IMetaVaultFactory public metaVaultFactory;
    IPriceReader priceReader;
    address public multisig;

    constructor() {
        // vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), 27965000)); // May-19-2025 09:53:57 AM +UTC
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), 36147180)); // Jun-27-2025 08:28:28 AM +UTC
        metaVault = IMetaVault(SonicConstantsLib.METAVAULT_metaUSD);
        metaVaultFactory = IMetaVaultFactory(IPlatform(PLATFORM).metaVaultFactory());
        multisig = IPlatform(PLATFORM).multisig();
        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());

        _upgradeMetaVault(SonicConstantsLib.METAVAULT_metaUSD);
    }

    function testChangeWhitelist() public {
        address user1 = address(1);
        address user2 = address(2);

        // --------------- Initially there are no whitelisted users
        vm.expectRevert(IMetaVault.NotWhitelisted.selector);
        vm.prank(user1);
        metaVault.setLastBlockDefenseDisabledTx(true);

        // --------------- User 1 is whitelisted, user 2 is not
        vm.prank(multisig);
        metaVault.changeWhitelist(user1, true);
        assertEq(metaVault.whitelisted(user1), true, "User 1 should be whitelisted 1");
        assertEq(metaVault.whitelisted(user2), false, "User 2 should NOT be whitelisted 1");

        vm.prank(user1);
        metaVault.setLastBlockDefenseDisabledTx(true);

        vm.expectRevert(IMetaVault.NotWhitelisted.selector);
        vm.prank(user2);
        metaVault.setLastBlockDefenseDisabledTx(true);

        // --------------- Both users are whitelisted
        vm.prank(multisig);
        metaVault.changeWhitelist(user2, true);
        assertEq(metaVault.whitelisted(user1), true, "User 1 should be whitelisted 2");
        assertEq(metaVault.whitelisted(user2), true, "User 2 should be whitelisted 2");

        vm.prank(user1);
        metaVault.setLastBlockDefenseDisabledTx(true);

        vm.prank(user2);
        metaVault.setLastBlockDefenseDisabledTx(false);


        // --------------- User 2 is whitelisted, user 1 is not
        vm.prank(multisig);
        metaVault.changeWhitelist(user1, false);
        assertEq(metaVault.whitelisted(user1), false, "User 1 should NOT be whitelisted 3");
        assertEq(metaVault.whitelisted(user2), true, "User 2 should be whitelisted 3");

        vm.expectRevert(IMetaVault.NotWhitelisted.selector);
        vm.prank(user1);
        metaVault.setLastBlockDefenseDisabledTx(true);

        vm.prank(user2);
        metaVault.setLastBlockDefenseDisabledTx(false);

        // --------------- Both users are not whitelisted
        vm.prank(multisig);
        metaVault.changeWhitelist(user2, false);
        assertEq(metaVault.whitelisted(user1), false, "User 1 should NOT be whitelisted 4");
        assertEq(metaVault.whitelisted(user2), false, "User 2 should NOT be whitelisted 4");

        vm.expectRevert(IMetaVault.NotWhitelisted.selector);
        vm.prank(user1);
        metaVault.setLastBlockDefenseDisabledTx(true);

        vm.expectRevert(IMetaVault.NotWhitelisted.selector);
        vm.prank(user2);
        metaVault.setLastBlockDefenseDisabledTx(true);
    }

    function testWhitelist() public {
        address user = address(1);
        address strategy = address(2);

        vm.prank(multisig);
        metaVault.changeWhitelist(strategy, true);

        // ------------------------- Enable defence in the MetaVaults, disable defence in all CVaults
        vm.prank(multisig);
        metaVault.setLastBlockDefenseDisabled(false);
        address[] memory vaults = metaVault.vaults();
        for (uint i = 0; i < vaults.length; ++i) {
            console.log(vaults[i]);
            vm.prank(multisig);
            IStabilityVault(vaults[i]).setLastBlockDefenseDisabled(true);
        }

        // ------------------------- User deposits an amount
        address[] memory assets = metaVault.assetsForDeposit();
        uint[] memory depositAmounts = _getAmountsForDeposit(500, assets);
        _dealAndApprove(address(1), address(metaVault), assets, depositAmounts);

        vm.prank(user);
        IStabilityVault(metaVault).depositAssets(assets, depositAmounts, 0, user);

        // ------------------------- Ensure that user is not able to deposit/withdraw/transfer
        assertEq(metaVault.whitelisted(user), false, "user is not yet whitelisted");
        _tryDepositWithdrawTransfer(user, true);

        // ------------------------- Add user to whitelist and try again (this time successfully)
        vm.prank(strategy);
        metaVault.setLastBlockDefenseDisabledTx(true);

        _tryDepositWithdrawTransfer(user, false);

        // ------------------------- Enable last-block-defence back and try again (unsuccessfully)
        vm.prank(strategy);
        metaVault.setLastBlockDefenseDisabledTx(false);

        _tryDepositWithdrawTransfer(user, true);

        // ------------------------- Disable last-block-defence, change block - defence is restored back
        vm.prank(strategy);
        metaVault.setLastBlockDefenseDisabledTx(true);

        vm.rollFork(block.number + 1);

        _tryDepositWithdrawTransfer(user, true);

    }

    //region ------------------------- Internal logic
    function _tryDepositWithdrawTransfer(address user, bool shouldRevert) internal {
        uint snapshot = vm.snapshot();

        // ------------------------ deposit
        address[] memory assets = metaVault.assetsForDeposit();
        uint[] memory depositAmounts = _getAmountsForDeposit(500, assets);
        _dealAndApprove(address(1), address(metaVault), assets, depositAmounts);

        if (shouldRevert) {
            vm.expectRevert(IStabilityVault.WaitAFewBlocks.selector);
        }
        vm.prank(user);
        IStabilityVault(metaVault).depositAssets(assets, depositAmounts, 0, user);

        // ------------------------ withdraw
        assets = metaVault.assetsForWithdraw();

        uint balance = metaVault.balanceOf(user);
        if (shouldRevert) {
            vm.expectRevert(IStabilityVault.WaitAFewBlocks.selector);
        }
        vm.prank(user);
        IStabilityVault(metaVault).withdrawAssets(assets, balance / 2, new uint[](1));

        // ------------------------ transfer
        balance = metaVault.balanceOf(user);
        if (shouldRevert) {
            vm.expectRevert(IStabilityVault.WaitAFewBlocks.selector);
        }
        vm.prank(user);
        IStabilityVault(metaVault).transfer(address(this), balance);

        vm.revertTo(snapshot);
    }
    //endregion ------------------------- Internal logic

    //region --------------------------------------- Helper functions
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
    //endregion --------------------------------------- Helper functions

}
