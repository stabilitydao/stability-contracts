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

/// @dev TODO tests for whitelist
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
    }

    function testWhitelist() public {
        address user = address(1);

        // ------------------------- Enable defence in the MetaVaults, disable defence in all CVaults
        vm.prank(multisig);
        metaVault.setLastBlockDefenseDisabled(false);
        address[] memory vaults = metaVault.vaults();
        for (uint i = 0; i < vaults.length; ++i) {
            console.log(vaults[i]);
            vm.prank(multisig);
            IStabilityVault(vaults[i]).setLastBlockDefenseDisabled(true);
        }

        // ------------------------- User deposit an amount
        address[] memory assets = metaVault.assetsForDeposit();
        uint[] memory depositAmounts = _getAmountsForDeposit(500, assets);
        _dealAndApprove(address(1), address(metaVault), assets, depositAmounts);

        vm.prank(user);
        IStabilityVault(metaVault).depositAssets(assets, depositAmounts, 0, user);

        // ------------------------- Ensure that user is not able to deposit/withdraw/transfer
        assertEq(metaVault.whitelisted(user), false, "user is not yet whitelisted");
        _tryDepositWithdrawTransfer(user, true);

        // ------------------------- Add user to whitelist and try again (this time successfully)
        vm.prank(multisig);
        metaVault.changeWhitelist(user, true);
        assertEq(metaVault.whitelisted(user), true, "user is whitelisted");
        _tryDepositWithdrawTransfer(user, false);

        // ------------------------- Remove user from whitelist and try again (unsuccessfully)
        vm.prank(multisig);
        metaVault.changeWhitelist(user, false);
        assertEq(metaVault.whitelisted(user), false, "user is not whitelisted anymore");
        _tryDepositWithdrawTransfer(user, true);
    }

    //region ------------------------- Internal logic
    function _tryDepositWithdrawTransfer(address user, bool shouldRevert) internal {
        console.log("_tryDepositWithdrawTransfer");
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
        console.log("deposited");

        // ------------------------ withdraw
        assets = metaVault.assetsForWithdraw();

        uint balance = metaVault.balanceOf(user);
        if (shouldRevert) {
            vm.expectRevert(IStabilityVault.WaitAFewBlocks.selector);
        }
        vm.prank(user);
        IStabilityVault(metaVault).withdrawAssets(assets, balance / 2, new uint[](1));
        console.log("withdrawn");

        // ------------------------ transfer
        balance = metaVault.balanceOf(user);
        if (shouldRevert) {
            vm.expectRevert(IStabilityVault.WaitAFewBlocks.selector);
        }
        vm.prank(user);
        IStabilityVault(metaVault).transfer(address(this), balance);
        console.log("transferred");

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

    //endregion --------------------------------------- Helper functions

}
