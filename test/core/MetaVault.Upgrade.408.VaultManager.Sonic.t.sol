// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AaveStrategy} from "../../src/strategies/AaveStrategy.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IchiSwapXFarmStrategy} from "../../src/strategies/IchiSwapXFarmStrategy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {MetaVault, IMetaVault, IStabilityVault} from "../../src/core/vaults/MetaVault.sol";
import {SiloFarmStrategy} from "../../src/strategies/SiloFarmStrategy.sol";
import {SiloManagedFarmStrategy} from "../../src/strategies/SiloManagedFarmStrategy.sol";
import {SiloStrategy} from "../../src/strategies/SiloStrategy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {console, Test} from "forge-std/Test.sol";
import {Factory} from "../../src/core/Factory.sol";
import {IProxy} from "../../src/interfaces/IProxy.sol";

/// @dev #408: introduce vault manager
contract MetaVaultUpgrade408VaultManagerSonicTest is Test {
    uint internal constant FORK_BLOCK = 51289172; // Oct-20-2025 07:13:57 AM +UTC

    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVault public metaVault;
    IMetaVaultFactory public metaVaultFactory;
    address public multisig;
    IPriceReader public priceReader;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        metaVault = IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);
        metaVaultFactory = IMetaVaultFactory(IPlatform(PLATFORM).metaVaultFactory());
        multisig = IPlatform(PLATFORM).multisig();

        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());

        _upgradeMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);
    }

    function testAddVaultVaultManagerIsNotSet() public {
        address vault = SonicConstantsLib.VAULT_C_USDC_S_49;

        address[] memory vaults = metaVault.vaults();
        for (uint i; i < vaults.length; ++i) {
            assertNotEq(vaults[i], vault, "vault is not present before addition");
        }

        // ------------------------ only multisig is able to add vault because vault manager is not set
        assertEq(metaVault.vaultManager(), address(0), "vault manager is not set");

        // for simplicity set 100% for the new vault
        uint[] memory newTargetProportions = new uint[](vaults.length + 1);
        newTargetProportions[vaults.length] = 1e18;

        vm.expectRevert();
        vm.prank(address(this));
        metaVault.addVault(vault, newTargetProportions);

        // ------------------------ multisig can add a vault
        vm.prank(multisig);
        metaVault.addVault(vault, newTargetProportions);

        // ------------------------ vault is added
        uint indexNewVault = type(uint).max;
        vaults = metaVault.vaults();
        for (uint i; i < vaults.length; ++i) {
            if (vaults[i] == vault) {
                indexNewVault = i;
                break;
            }
        }

        assertEq(indexNewVault, vaults.length - 1, "vault is added to the end");
    }

    function testAddVaultVaultManagerIsSet() public {
        address vault = SonicConstantsLib.VAULT_C_USDC_S_49;

        address[] memory vaults = metaVault.vaults();
        for (uint i; i < vaults.length; ++i) {
            assertNotEq(vaults[i], vault, "vault is not present before addition");
        }

        // ------------------------ set vault manager
        address vaultManager = makeAddr("VaultManager");

        vm.prank(multisig);
        metaVault.setVaultManager(vaultManager);

        assertEq(metaVault.vaultManager(), vaultManager, "vault manager is set");

        // ------------------------ only vault manager is able to add vault because vault manager is not set

        // for simplicity set 100% for the new vault
        uint[] memory newTargetProportions = new uint[](vaults.length + 1);
        newTargetProportions[vaults.length] = 1e18;

        vm.expectRevert();
        vm.prank(address(this));
        metaVault.addVault(vault, newTargetProportions);

        vm.expectRevert();
        vm.prank(multisig);
        metaVault.addVault(vault, newTargetProportions);

        // ------------------------ vault manager can add the vault
        vm.prank(vaultManager);
        metaVault.addVault(vault, newTargetProportions);

        // ------------------------ vault is added
        uint indexNewVault = type(uint).max;
        vaults = metaVault.vaults();
        for (uint i; i < vaults.length; ++i) {
            if (vaults[i] == vault) {
                indexNewVault = i;
                break;
            }
        }

        assertEq(indexNewVault, vaults.length - 1, "vault is added to the end");
    }

    function testRemoveVaultVaultManagerIsNotSet() public {
        address vault = _prepareVaultToRemove(2);

        address[] memory vaults = metaVault.vaults();
        assertEq(vaults[2], vault, "vault is present before removal");

        // ------------------------ only multisig is able to remove vault because vault manager is not set
        assertEq(metaVault.vaultManager(), address(0), "vault manager is not set");

        vm.expectRevert();
        vm.prank(address(this));
        metaVault.removeVault(vault);

        // ------------------------ multisig can remove vault
        vm.prank(multisig);
        metaVault.removeVault(vault);

        // ------------------------ vault is removed
        vaults = metaVault.vaults();
        for (uint i; i < vaults.length; ++i) {
            assertNotEq(vaults[i], vault, "vault is removed");
        }
    }

    function testRemoveVaultVaultManagerIsSet() public {
        address vault = _prepareVaultToRemove(2);

        address[] memory vaults = metaVault.vaults();
        assertEq(vaults[2], vault, "vault is present before removal");

        address vaultManager = makeAddr("VaultManager");

        vm.prank(multisig);
        metaVault.setVaultManager(vaultManager);

        assertEq(metaVault.vaultManager(), vaultManager, "vault manager is set");

        // ------------------------ only vault manager is able to remove vault
        vm.expectRevert();
        vm.prank(address(this));
        metaVault.removeVault(vault);

        // ------------------------ even multisig is not able to remove vault
        vm.expectRevert();
        vm.prank(multisig);
        metaVault.removeVault(vault);

        // ------------------------ vault manager can remove vault
        vm.prank(vaultManager);
        metaVault.removeVault(vault);

        // ------------------------ vault is removed
        vaults = metaVault.vaults();
        for (uint i; i < vaults.length; ++i) {
            assertNotEq(vaults[i], vault, "vault is removed");
        }
    }

    function testChangeProportionsVaultManagerIsNotSet() public {
        address[] memory vaults = metaVault.vaults();

        // for simplicity set 100% for the the last vault
        uint[] memory newTargetProportions = new uint[](vaults.length);
        newTargetProportions[vaults.length - 1] = 1e18;

        // ------------------------ not-multisig cannot change proportions
        vm.expectRevert();
        vm.prank(address(this));
        metaVault.setTargetProportions(newTargetProportions);

        // ------------------------ multisig can change proportions
        vm.prank(multisig);
        metaVault.setTargetProportions(newTargetProportions);

        // ------------------------ proportions are changed
        uint[] memory updatedProportions = metaVault.targetProportions();

        for (uint i; i < vaults.length; ++i) {
            assertEq(updatedProportions[i], newTargetProportions[i], "proportion for vault is updated");
        }
    }

    function testChangeProportionsVaultManagerIsSet() public {
        address[] memory vaults = metaVault.vaults();

        // for simplicity set 100% for the the last vault
        uint[] memory newTargetProportions = new uint[](vaults.length);
        newTargetProportions[vaults.length - 1] = 1e18;

        // ------------------------ set vault manager
        address vaultManager = makeAddr("VaultManager");

        vm.prank(multisig);
        metaVault.setVaultManager(vaultManager);

        assertEq(metaVault.vaultManager(), vaultManager, "vault manager is set");

        // ------------------------ not-vault-manager cannot change proportions
        vm.expectRevert();
        vm.prank(address(this));
        metaVault.setTargetProportions(newTargetProportions);

        vm.expectRevert();
        vm.prank(multisig);
        metaVault.setTargetProportions(newTargetProportions);

        // ------------------------ vault-manager can change proportions
        vm.prank(vaultManager);
        metaVault.setTargetProportions(newTargetProportions);

        // ------------------------ proportions are changed
        uint[] memory updatedProportions = metaVault.targetProportions();

        for (uint i; i < vaults.length; ++i) {
            assertEq(updatedProportions[i], newTargetProportions[i], "proportion for vault is updated");
        }
    }

    //region ------------------------------ Internal logic
    /// @notice Ensure that the vault has enough liquidity to withdraw all assets
    function _isVaultRemovable(uint valueIndex) internal view returns (bool) {
        address vault = metaVault.vaults()[valueIndex];
        return IStabilityVault(vault).maxWithdraw(address(metaVault), 0)
            == IStabilityVault(vault).balanceOf(address(metaVault));
    }

    function _prepareVaultToRemove(uint vaultIndex) internal returns (address vault) {
        vault = metaVault.vaults()[vaultIndex];

        // ----------------------------- Remove all actives from the volt so that only dust remains in it
        uint threshold = metaVault.USD_THRESHOLD();
        uint step;

        do {
            uint amount = _getVaultOwnerAmountUsd(vault, address(metaVault));
            // console.log("amount before", amount);
            if (amount < threshold) break;

            // Set target vault to zero
            _prepareProportionsToWithdraw(vaultIndex);

            _makeWithdraw();
            _prepareProportionsToDeposit(vaultIndex == 0 ? 1 : 0);

            amount = _getVaultOwnerAmountUsd(vault, address(metaVault));
            // console.log("amount after", step, amount, threshold);
            if (amount < threshold) break;

            _makeDeposit();
            ++step;
        } while (step < 200);

        _prepareProportionsToWithdraw(vaultIndex);

        assertLt(
            _getVaultOwnerAmountUsd(vault, address(metaVault)),
            threshold,
            "Vault shouldn't have more than threshold amount"
        );

        return vault;
    }

    function _makeWithdrawDeposit() internal {
        _makeWithdraw();
        _makeDeposit();
    }

    function _makeWithdraw() internal {
        address[] memory assets = metaVault.assetsForWithdraw();

        uint amountToWithdraw = metaVault.maxWithdraw(SonicConstantsLib.METAVAULT_METAUSD) / 7;
        //        console.log("max", metaVault.maxWithdraw(SonicConstantsLib.METAVAULT_METAUSD));
        //        console.log("amountToWithdraw", amountToWithdraw);

        vm.prank(SonicConstantsLib.METAVAULT_METAUSD);
        metaVault.withdrawAssets(assets, amountToWithdraw, new uint[](1));
        vm.roll(block.number + 6);
    }

    function _makeDeposit() internal {
        address[] memory assets = metaVault.assetsForDeposit();
        uint[] memory maxAmounts = new uint[](1);
        maxAmounts[0] = IERC20(assets[0]).balanceOf(address(metaVault));

        vm.prank(SonicConstantsLib.METAVAULT_METAUSD);
        IERC20(assets[0]).approve(address(metaVault), maxAmounts[0]);

        vm.prank(SonicConstantsLib.METAVAULT_METAUSD);
        metaVault.depositAssets(assets, maxAmounts, 0, SonicConstantsLib.METAVAULT_METAUSD);
        vm.roll(block.number + 6);
    }

    function _getVaultOwnerAmountUsd(address vault, address owner) internal view returns (uint) {
        (uint vaultTvl,) = IStabilityVault(vault).tvl();
        uint vaultSharesBalance = IERC20(vault).balanceOf(owner);
        uint vaultTotalSupply = IERC20(vault).totalSupply();
        return
            vaultTotalSupply == 0 ? 0 : Math.mulDiv(vaultSharesBalance, vaultTvl, vaultTotalSupply, Math.Rounding.Floor);
    }

    function _prepareProportionsToWithdraw(uint fromIndex) internal {
        multisig = IPlatform(PLATFORM).multisig();
        uint countVaults = metaVault.vaults().length;

        uint[] memory props = metaVault.currentProportions();
        uint sumProps;
        for (uint i; i < props.length; ++i) {
            sumProps += props[i];
        }
        if (sumProps > 1e18) {
            uint delta = sumProps - 1e18;
            for (uint i; i < props.length; ++i) {
                if (props[i] > delta) {
                    props[i] -= delta;
                    break;
                }
            }
        } else if (sumProps < 1e18) {
            uint delta = 1e18 - sumProps;
            props[0] += delta;
        }
        uint part1 = props[fromIndex] / 2;
        uint part2 = props[fromIndex] - part1;
        props[fromIndex] = 0;

        uint toIndex = fromIndex + 1;
        if (toIndex >= countVaults) toIndex = 0;
        props[toIndex] += part1;

        toIndex = fromIndex + 1;
        if (toIndex >= countVaults) toIndex = 0;
        props[toIndex] += part2;

        vm.prank(multisig);
        metaVault.setTargetProportions(props);

        //        props = metaVault.targetProportions();
        //        for (uint i; i < current.length; ++i) {
        //            // uint[] memory current = metaVault.currentProportions();
        //            console.log("i, current, target", i, current[i], props[i]);
        //        }
    }

    function _prepareProportionsToDeposit(uint toIndex) internal {
        multisig = IPlatform(PLATFORM).multisig();

        uint sumProps = 0;
        uint[] memory props = metaVault.targetProportions();
        for (uint i; i < props.length; ++i) {
            if (i != toIndex) {
                props[i] = 1e16;
                sumProps += props[i];
            }
        }
        props[toIndex] = 1e18 - sumProps;

        vm.prank(multisig);
        metaVault.setTargetProportions(props);

        //        props = metaVault.targetProportions();
        //        uint[] memory current = metaVault.currentProportions();
        //        for (uint i; i < current.length; ++i) {
        //            console.log("i, current, target", i, current[i], props[i]);
        //        }
    }

    function _getDiffPercent18(uint x, uint y) internal pure returns (uint) {
        if (x == 0) {
            return y == 0 ? 0 : 1e18;
        }
        return x > y ? (x - y) * 1e18 / x : (y - x) * 1e18 / x;
    }

    //endregion ------------------------------ Internal logic

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

    function _dealAndApprove(address user, address metavault, address[] memory assets, uint[] memory amounts) internal {
        for (uint j; j < assets.length; ++j) {
            deal(assets[j], user, amounts[j]);
            vm.prank(user);
            IERC20(assets[j]).approve(metavault, amounts[j]);
        }
    }
    //endregion ------------------------------ Auxiliary Functions
}
