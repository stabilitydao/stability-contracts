// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console, Test} from "forge-std/Test.sol";
import {IERC4626, IERC20} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MetaVault} from "../../src/core/vaults/MetaVault.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {IMetaVault} from "../../src/interfaces/IMetaVault.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AaveMerklFarmStrategy} from "../../src/strategies/AaveMerklFarmStrategy.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";

contract MetaVault360WithdrawUnderlyingSonicUpgrade is Test {
    uint public constant FORK_BLOCK = 41729414; // Aug-05-2025 12:30:58 PM +UTC

    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public multisig;
    IMetaVault public metaVault;
    IMetaVaultFactory public metaVaultFactory;

    address public constant HOLDER = SonicConstantsLib.WRAPPED_METAVAULT_metaUSD;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));
        multisig = IPlatform(PLATFORM).multisig();
        metaVaultFactory = IMetaVaultFactory(SonicConstantsLib.METAVAULT_FACTORY);
        metaVault = IMetaVault(SonicConstantsLib.METAVAULT_metaUSD);
    }

    function testAMF() public {
        (, IStabilityVault vault) = _prepareSubVaultToWithdraw(
            SonicConstantsLib.METAVAULT_metaUSDC, SonicConstantsLib.VAULT_C_Credix_USDC_AMFa0
        );
        _upgradeAmfStrategy(address(IVault(SonicConstantsLib.VAULT_C_Credix_USDC_AMFa0).strategy()));

        // ----------------------------------- detect underlying and amount to withdraw
        IStrategy strategy = IVault(address(vault)).strategy();

        vm.prank(multisig);
        AaveMerklFarmStrategy(address(strategy)).setUnderlying();

        assertNotEq(strategy.underlying(), address(0), "Underlying should not be zero address");

        // ----------------------------------- withdraw underlying from the given vault
        uint value = Math.mulDiv(vault.balanceOf(HOLDER), strategy.total(), vault.totalSupply(), Math.Rounding.Ceil);

        address[] memory assets = new address[](1);
        assets[0] = strategy.underlying();

        uint balanceUnderlyingBefore = IERC20(assets[0]).balanceOf(HOLDER);
        vm.prank(HOLDER);
        vault.withdrawAssets(assets, value, new uint[](1)); // todo min amounts
        uint balanceUnderlyingAfter = IERC20(assets[0]).balanceOf(HOLDER);

        assertEq(
            balanceUnderlyingAfter - balanceUnderlyingBefore, value, "Withdrawn amount should match expected value"
        );
    }

    // todo
    function testEclabs() internal {
        (, IStabilityVault vault) = _prepareSubVaultToWithdraw(
            SonicConstantsLib.METAVAULT_metaUSDC, SonicConstantsLib.VAULT_C_Enclabs_USDC_CVv8
        );

        // ----------------------------------- detect underlying and amount to withdraw
        IStrategy strategy = IVault(address(vault)).strategy();
        assertNotEq(strategy.underlying(), address(0), "Underlying should not be zero address");

        // ----------------------------------- withdraw underlying from the given vault
        uint value = Math.mulDiv(vault.balanceOf(HOLDER), strategy.total(), vault.totalSupply(), Math.Rounding.Ceil);

        address[] memory assets = new address[](1);
        assets[0] = strategy.underlying();

        uint balanceUnderlyingBefore = IERC20(assets[0]).balanceOf(HOLDER);
        vm.prank(HOLDER);
        vault.withdrawAssets(assets, value, new uint[](1)); // todo min amounts
        uint balanceUnderlyingAfter = IERC20(assets[0]).balanceOf(HOLDER);

        assertEq(
            balanceUnderlyingAfter - balanceUnderlyingBefore, value, "Withdrawn amount should match expected value"
        );
    }

    //region ---------------------------------------------- Internal
    function _prepareSubVaultToWithdraw(
        address metaVault_,
        address subVault_
    ) internal returns (IMetaVault subMetaVault, IStabilityVault vault) {
        // ----------------------------------- upgrade contracts
        vm.prank(multisig);
        _upgradeMetaVault(metaVault_);

        // ----------------------------------- set given vault for withdraw
        subMetaVault = IMetaVault(metaVault_);
        {
            uint vaultIndex = _getVaultIndex(subMetaVault, subVault_);
            _setProportionsForWithdraw(subMetaVault, vaultIndex, vaultIndex == 0 ? 1 : 0);
        }
        vault = IStabilityVault(subMetaVault.vaultForWithdraw());

        assertEq(metaVault.vaultForWithdraw(), metaVault_, "Metavault for withdraw should be the expected one");
        assertEq(address(vault), subVault_, "Subvault for withdraw should be the expected one");
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

        _showProportions(metaVault_);
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

    //endregion ---------------------------------------------- Helpers
}
