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
import {IVault} from "../../src/interfaces/IVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IAToken} from "../../src/integrations/aave/IAToken.sol";
import {IPool} from "../../src/integrations/aave/IPool.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {AaveStrategy} from "../../src/strategies/AaveStrategy.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";

contract AUpgradeTest is Test {
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

    /// @notice #326: Metavault is not able to withdraw from Aave strategy all amount because of the lack of liquidity in aToken
    function testMetaVaultUpdate326() public {
        IVault vault = IVault(SonicConstantsLib.VAULT_C_USDC_Stability_StableJack);
        IStrategy strategy = vault.strategy();
        address[] memory assets = vault.assets();

        // ------------------- upgrade strategy
        // _upgradeCVault(SonicConstantsLib.VAULT_C_USDC_Stability_StableJack);
        _upgradeAaveStrategy(address(strategy));

        IAToken aToken = IAToken(AaveStrategy(address(strategy)).aaveToken());

        // ------------------- get max amount ot vault tokens that can be withdrawn
        uint maxWithdraw = vault.balanceOf(SonicConstantsLib.METAVAULT_metaUSDC);

        // ------------------- our balance and max available liquidity in AAVE token
        uint aTokenBalance = aToken.balanceOf(address(strategy));
        uint availableLiquidity = strategy.maxWithdrawAssets()[0];

        // ------------------- amount of vault tokens that can be withdrawn
        uint balanceToWithdraw = availableLiquidity > aTokenBalance
            ? maxWithdraw
            : availableLiquidity * maxWithdraw / aTokenBalance - 1;

        // ------------------- ensure that we cannot withdraw amount on 1% more than the calculated balance
        vm.expectRevert();
        vm.prank(SonicConstantsLib.METAVAULT_metaUSDC);
        vault.withdrawAssets(assets, balanceToWithdraw * 101/100, new uint[](1));

        // ------------------- ensure that we can withdraw calculated amount of vault tokens
        vm.prank(SonicConstantsLib.METAVAULT_metaUSDC);
        vault.withdrawAssets(assets, balanceToWithdraw, new uint[](1));

        // ------------------- check poolTvl
        (uint price, ) = priceReader.getPrice(assets[0]);

        assertEq(
            aToken.totalSupply() * price / (10**IERC20Metadata(assets[0]).decimals()),
            strategy.poolTvl()
        );
    }


    //region ------------------------------ Auxiliary Functions
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

    function _upgradeAaveStrategy(address strategyAddress) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new AaveStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.AAVE,
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
