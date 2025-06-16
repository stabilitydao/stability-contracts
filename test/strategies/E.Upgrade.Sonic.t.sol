// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IEVC, IEthereumVaultConnector} from "../../src/integrations/euler/IEthereumVaultConnector.sol";
import {IEulerVault} from "../../src/integrations/euler/IEulerVault.sol";
import {EulerStrategy} from "../../src/strategies/EulerStrategy.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IMetaVault, IStabilityVault} from "../../src/core/vaults/MetaVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {console, Test, Vm} from "forge-std/Test.sol";

contract EUpgradeTest is Test {
    uint public constant FORK_BLOCK = 33508152; // Jun-12-2025 05:49:24 AM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVault public metaVault;
    IMetaVaultFactory public metaVaultFactory;
    address public multisig;
    IPriceReader public priceReader;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        metaVault = IMetaVault(SonicConstantsLib.METAVAULT_metaUSDC);
        metaVaultFactory = IMetaVaultFactory(IPlatform(PLATFORM).metaVaultFactory());
        multisig = IPlatform(PLATFORM).multisig();

        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
    }

    /// @notice #326: Add maxWithdrawAssets and poolTvl to IStrategy
    function testMetaVaultUpdate326() public {
        IVault vault = IVault(SonicConstantsLib.VAULT_C_scUSD_Euler_Re7Labs);
        IStrategy strategy = vault.strategy();
        address[] memory assets = vault.assets();

        // ------------------- upgrade strategy
        // _upgradeCVault(SonicConstantsLib.VAULT_C_scUSD_Euler_Re7Labs);
        _upgradeEulerStrategy(address(strategy));

        // ------------------- get max amount ot vault tokens that can be withdrawn
        uint maxWithdraw = vault.balanceOf(SonicConstantsLib.METAVAULT_metascUSD);

        // ------------------- our balance and max available liquidity in Euler token
        EulerStrategy eulerStrategy = EulerStrategy(address(strategy));
        IEulerVault eulerVault = IEulerVault(eulerStrategy.underlying());
        uint cash = eulerVault.cash();

        // ------------------- borrow almost all cash
        _borrowAlmostAllCash(eulerVault, cash);

        uint balanceAssets = eulerVault.convertToAssets(eulerVault.balanceOf(address(strategy)));
        uint availableLiquidity = strategy.maxWithdrawAssets()[0];

        // ------------------- amount of vault tokens that can be withdrawn
        uint balanceToWithdraw =
            availableLiquidity == balanceAssets ? maxWithdraw : availableLiquidity * maxWithdraw / balanceAssets - 1;

        // ------------------- ensure that we cannot withdraw amount on 1% more than the calculated balance
        vm.expectRevert();
        vm.prank(SonicConstantsLib.METAVAULT_metascUSD);
        vault.withdrawAssets(assets, maxWithdraw, new uint[](1));

        // ------------------- ensure that we can withdraw calculated amount of vault tokens
        vm.prank(SonicConstantsLib.METAVAULT_metascUSD);
        vault.withdrawAssets(assets, balanceToWithdraw, new uint[](1));

        // ------------------- check poolTvl
        (uint price,) = priceReader.getPrice(assets[0]);

        assertEq(eulerVault.totalAssets() * price / (10 ** IERC20Metadata(assets[0]).decimals()), strategy.poolTvl());
    }

    //region ------------------------------ Auxiliary Functions
    function _borrowAlmostAllCash(IEulerVault eulerVault, uint cash) internal {
        IEulerVault collateralVault = IEulerVault(SonicConstantsLib.EULER_VAULT_wS_Re7);
        IEthereumVaultConnector evc = IEthereumVaultConnector(payable(collateralVault.EVC()));

        uint collateralAmount = cash * 10 * 10 ** 12; // borrow scUSD, collateral is wS

        deal(SonicConstantsLib.TOKEN_wS, address(this), collateralAmount);
        IERC20(SonicConstantsLib.TOKEN_wS).approve(address(collateralVault), collateralAmount);

        uint borrowAmount = cash - 1e6; // * 9999 / 10000;

        // console.log("Enabling borrow controller...");
        evc.enableController(address(this), address(eulerVault));

        // console.log("Enabling collateral...");
        evc.enableCollateral(address(this), address(collateralVault));

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](2);

        bytes memory depositData = abi.encodeWithSelector(IEulerVault.deposit.selector, collateralAmount, address(this));
        items[0] = IEVC.BatchItem({
            targetContract: address(collateralVault),
            onBehalfOfAccount: address(this),
            value: 0,
            data: depositData
        });

        bytes memory borrowData = abi.encodeWithSelector(IEulerVault.borrow.selector, borrowAmount, address(this));
        items[1] = IEVC.BatchItem({
            targetContract: address(eulerVault),
            onBehalfOfAccount: address(this),
            value: 0,
            data: borrowData
        });

        uint cashBefore = eulerVault.cash();
        evc.batch(items);
        assertGt(cashBefore, eulerVault.cash(), "Euler cash was not borrowed");
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

    function _upgradeCVault(address vault) internal {
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

        factory.upgradeVaultProxy(vault);
    }

    function _upgradeEulerStrategy(address strategyAddress) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new EulerStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.EULER,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(strategyAddress);
    }
    //endregion ------------------------------ Auxiliary Functions
}
