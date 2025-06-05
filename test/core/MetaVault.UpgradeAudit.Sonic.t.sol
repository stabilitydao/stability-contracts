// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console, Test, Vm} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626, IERC20} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MetaVault, IMetaVault, IStabilityVault} from "../../src/core/vaults/MetaVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";

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
        _upgradeMetaVault();

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
                type(uint256).max, // revert ExceedSlippage
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

            (sharesToCreate, ) = abi.decode(errorData, (uint, uint));
            vm.revertToState(snapshotId);
        }

        // ----------- get values of balanceOut
        snapshotId = vm.snapshotState();
        uint totalSupplyBefore = metaVault.totalSupply();
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
                (, , balanceOut) = abi.decode(logs[i].data, (address[], uint[], uint));
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

    //region ------------------------------ Auxiliary Functions
    function _upgradeMetaVault() internal {
        // Upgrade MetaVault to the new implementation
        address vaultImplementation = address(new MetaVault());
        vm.prank(multisig);
        metaVaultFactory.setMetaVaultImplementation(vaultImplementation);
        address[] memory metaProxies = new address[](1);
        metaProxies[0] = address(metaVault);
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
    //endregion ------------------------------ Auxiliary Functions

}
