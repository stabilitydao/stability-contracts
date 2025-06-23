// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CVault} from "../../src/core/vaults/CVault.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626, IERC20} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ISiloVault} from "../../src/integrations/silo/ISiloVault.sol";
import {IVaultIncentivesModule} from "../../src/integrations/silo/IVaultIncentivesModule.sol";
import {IIncentivesClaimingLogic} from "../../src/integrations/silo/IIncentivesClaimingLogic.sol";
import {ISiloIncentivesControllerForVault} from "../../src/integrations/silo/ISiloIncentivesControllerForVault.sol";
import {IDistributionManager} from "../../src/integrations/silo/IDistributionManager.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IFarmingStrategy} from "../../src/interfaces/IFarmingStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IMetaVault} from "../../src/core/vaults/MetaVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {console, Test, Vm} from "forge-std/Test.sol";
import {SiloManagedFarmStrategy} from "../../src/strategies/SiloManagedFarmStrategy.sol";

contract SiMFUpgradeXSiloTest is Test {
    uint public constant FORK_BLOCK = 35508919; // Jun-23-2025 01:42:05 PM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    address public constant METAVAULT = SonicConstantsLib.METAVAULT_metaUSDC;
    address public constant VAULT_C_USDC_SiMF = 0xf6Fc4Ea6c1E6DcB68C5FFab82F6c0aD2D4c94df9; // todo move to SonicConstantsLib
    address public constant VAULT_C = VAULT_C_USDC_SiMF;
    IMetaVault public metaVault;
    IMetaVaultFactory public metaVaultFactory;
    address public multisig;
    IPriceReader public priceReader;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        metaVault = IMetaVault(METAVAULT);
        metaVaultFactory = IMetaVaultFactory(IPlatform(PLATFORM).metaVaultFactory());
        multisig = IPlatform(PLATFORM).multisig();

        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
    }

    /// @notice #335: Add support of xSilo in SiMF strategy
    function testXSiloSupport() public {
        IVault vault = IVault(VAULT_C);
        IStrategy strategy = vault.strategy();

        // ------------------- upgrade strategy
        // _upgradeCVault(SonicConstantsLib.VAULT_C);
        _upgradeManagedSiloFarmStrategy(address(strategy));

        // ------------------- our balance and max available liquidity
        SiloManagedFarmStrategy sifStrategy = SiloManagedFarmStrategy(address(strategy));
        IFactory.Farm memory farm = IFactory(IPlatform(PLATFORM).factory()).farm(sifStrategy.farmId());
        ISiloVault siloVault = ISiloVault(farm.addresses[0]);

        // ------------------- upgrade list of reward assets in farm
        _upgradeRewardAssetsInFarm(IFarmingStrategy(address(strategy)).farmId());

        // ------------------- get all available rewards
        uint amountBefore = _getRewards(address(strategy), siloVault, SonicConstantsLib.TOKEN_xSILO)
            + IERC20(SonicConstantsLib.TOKEN_xSILO).balanceOf(address(strategy));

        vm.prank(address(vault));
        strategy.doHardWork();

        uint amountAfter = _getRewards(address(strategy), siloVault,SonicConstantsLib.TOKEN_xSILO)
            + IERC20(SonicConstantsLib.TOKEN_xSILO).balanceOf(address(strategy));

        console.log("amountBefore", amountBefore);
        console.log("amountAfter", amountAfter);
    }

    //region ------------------------------ Auxiliary Functions
    function _getRewards(address strategy, ISiloVault siloVault, address rewardToken_) internal returns (uint amountOut) {
        siloVault.claimRewards();

        IVaultIncentivesModule vim = IVaultIncentivesModule(siloVault.INCENTIVES_MODULE());
        address[] memory claimingLogics = vim.getAllIncentivesClaimingLogics();

        for (uint i; i < claimingLogics.length; ++i) {
            IIncentivesClaimingLogic logic = IIncentivesClaimingLogic(claimingLogics[i]);
            ISiloIncentivesControllerForVault c = ISiloIncentivesControllerForVault(logic.VAULT_INCENTIVES_CONTROLLER());

            vm.prank(address(strategy));
            IDistributionManager.AccruedRewards[] memory accruedRewards = c.claimRewards(address(strategy));
            for (uint j; j < accruedRewards.length; ++j) {
                address rewardAsset = accruedRewards[j].rewardToken;
                uint amount = accruedRewards[j].amount;
                console.log("Claimed", amount, IERC20Metadata(rewardAsset).symbol(), rewardAsset);
                if (rewardAsset == rewardToken_) {
                    amountOut += amount;
                }
            }
        }

        return amountOut;
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

    function _upgradeManagedSiloFarmStrategy(address strategyAddress) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new SiloManagedFarmStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.SILO_MANAGED_FARM,
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

    function _upgradeRewardAssetsInFarm(uint farmId) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        IFactory.Farm memory f = factory.farm(farmId);
        f.rewardAssets = new address[](2);
        f.rewardAssets[0] = SonicConstantsLib.TOKEN_SILO;
        f.rewardAssets[1] = SonicConstantsLib.TOKEN_xSILO;

        vm.prank(multisig);
        factory.updateFarm(farmId, f);
    }
    //endregion ------------------------------ Auxiliary Functions
}
