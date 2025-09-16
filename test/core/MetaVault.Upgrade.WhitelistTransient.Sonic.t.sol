// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {MetaVault, IMetaVault, IStabilityVault} from "../../src/core/vaults/MetaVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";

/// @notice Special separate test to ensure that the last block defense is enabled after finishing the transaction.
/// @dev Test how _LastBlockDefenseDisabledTx works
/// @dev Key point: setUp and testSecondTransaction are executed in separate transactions.
contract MetaVaultSonicUpgradeWhitelistTransient is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVault public metaVault;
    IMetaVaultFactory public metaVaultFactory;
    IPriceReader priceReader;
    address public multisig;

    uint[] internal depositAmounts;
    address internal user;
    address[] internal assets;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), 36147180)); // Jun-27-2025 08:28:28 AM +UTC
        metaVault = IMetaVault(SonicConstantsLib.METAVAULT_METAUSD);
        metaVaultFactory = IMetaVaultFactory(IPlatform(PLATFORM).metaVaultFactory());
        multisig = IPlatform(PLATFORM).multisig();
        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
        user = address(1);
    }

    /// @notice First transaction: set up the MetaVault, whitelist a strategy, deposit some assets
    function setUp() public {
        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSD);

        address strategy = address(3);

        vm.prank(multisig);
        metaVault.changeWhitelist(strategy, true);

        // ------------------------- Enable defence in the MetaVaults, disable defence in all CVaults
        vm.prank(multisig);
        metaVault.setLastBlockDefenseDisabled(false);
        address[] memory vaults = metaVault.vaults();
        for (uint i = 0; i < vaults.length; ++i) {
            vm.prank(multisig);
            IStabilityVault(vaults[i]).setLastBlockDefenseDisabled(true);
        }

        // ------------------------- Add user to whitelist and try to deposit (successfully)
        vm.prank(strategy);
        metaVault.setLastBlockDefenseDisabledTx(uint(IMetaVault.LastBlockDefenseDisableMode.DISABLED_TX_UPDATE_MAPS_1));

        assets = metaVault.assetsForDeposit();
        depositAmounts = _getAmountsForDeposit(500, assets);
        _dealAndApprove(user, address(metaVault), assets, depositAmounts);

        vm.prank(user);
        IStabilityVault(metaVault).depositAssets(assets, depositAmounts, 0, user);
    }

    /// @notice Second transaction: ensure that we cannot make deposit (last block defense is auto-enabled)
    function testSecondTransaction() public {
        vm.expectRevert(IStabilityVault.WaitAFewBlocks.selector);
        vm.startPrank(user);
        IStabilityVault(metaVault).depositAssets(assets, depositAmounts, 0, user);
    }

    //region ------------------------- Internal logic
    function _tryDepositWithdrawTransfer(address user_, bool shouldRevert) internal {
        uint snapshot = vm.snapshotState();

        // ------------------------ deposit
        assets = metaVault.assetsForDeposit();
        depositAmounts = _getAmountsForDeposit(500, assets);
        _dealAndApprove(address(1), address(metaVault), assets, depositAmounts);

        if (shouldRevert) {
            vm.expectRevert(IStabilityVault.WaitAFewBlocks.selector);
        }
        vm.prank(user_);
        IStabilityVault(metaVault).depositAssets(assets, depositAmounts, 0, user_);

        // ------------------------ withdraw
        assets = metaVault.assetsForWithdraw();

        uint balance = metaVault.balanceOf(user_);
        if (shouldRevert) {
            vm.expectRevert(IStabilityVault.WaitAFewBlocks.selector);
        }
        vm.prank(user_);
        IStabilityVault(metaVault).withdrawAssets(assets, balance / 2, new uint[](1));

        // ------------------------ transfer
        balance = metaVault.balanceOf(user_);
        if (shouldRevert) {
            vm.expectRevert(IStabilityVault.WaitAFewBlocks.selector);
        }
        vm.prank(user_);
        IStabilityVault(metaVault).transfer(address(this), balance);

        vm.revertToState(snapshot);
    }
    //endregion ------------------------- Internal logic

    //region --------------------------------------- Helper functions
    function _getAmountsForDeposit(
        uint usdValue,
        address[] memory assets_
    ) internal view returns (uint[] memory _depositAmounts) {
        _depositAmounts = new uint[](assets_.length);
        for (uint j; j < assets_.length; ++j) {
            (uint price,) = priceReader.getPrice(assets_[j]);
            require(price > 0, "UniversalTest: price is zero. Forget to add swapper routes?");
            _depositAmounts[j] = usdValue * 10 ** IERC20Metadata(assets_[j]).decimals() * 1e18 / price;
        }
    }

    function _dealAndApprove(
        address user_,
        address metavault,
        address[] memory assets_,
        uint[] memory amounts
    ) internal {
        for (uint j; j < assets_.length; ++j) {
            deal(assets_[j], user_, amounts[j]);
            vm.prank(user_);
            IERC20(assets_[j]).approve(metavault, amounts[j]);
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
