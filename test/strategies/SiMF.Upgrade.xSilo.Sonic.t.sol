// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../src/adapters/libs/AmmAdapterIdLib.sol";
import "../../src/interfaces/IAmmAdapter.sol";
import "../../src/interfaces/ISwapper.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {IDistributionManager} from "../../src/integrations/silo/IDistributionManager.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626, IERC20} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IFarmingStrategy} from "../../src/interfaces/IFarmingStrategy.sol";
import {IIncentivesClaimingLogic} from "../../src/integrations/silo/IIncentivesClaimingLogic.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IMetaVault} from "../../src/core/vaults/MetaVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {ISiloIncentivesControllerForVault} from "../../src/integrations/silo/ISiloIncentivesControllerForVault.sol";
import {ISiloVault} from "../../src/integrations/silo/ISiloVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVaultIncentivesModule} from "../../src/integrations/silo/IVaultIncentivesModule.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {SiloManagedFarmStrategy} from "../../src/strategies/SiloManagedFarmStrategy.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {console, Test, Vm} from "forge-std/Test.sol";

/// @notice #335: Add support of xSilo in SiMF strategy
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
        _upgradeRewardAssetsInFarm(address(strategy));
        _addPoolForXSilo();

        // ------------------- get all available rewards
        uint amountBefore = _getRewards(address(strategy), siloVault, SonicConstantsLib.TOKEN_xSILO);
        uint balanceBefore = IERC20(SonicConstantsLib.TOKEN_xSILO).balanceOf(address(strategy));
        (, uint[] memory assetsAmountsBefore) = strategy.assetsAmounts();

        vm.prank(address(vault));
        strategy.doHardWork();

        uint amountAfter = _getRewards(address(strategy), siloVault, SonicConstantsLib.TOKEN_xSILO);
        uint balanceAfter = IERC20(SonicConstantsLib.TOKEN_xSILO).balanceOf(address(strategy));
        (, uint[] memory assetsAmountsAfter) = strategy.assetsAmounts();

        // ------------------- check results

        (uint price, ) = priceReader.getPrice(SonicConstantsLib.TOKEN_xSILO);
        uint expectedAmountUSD = (balanceBefore + amountBefore) * price / 1e18 / 1e18;

//        console.log("amountBefore", amountBefore, balanceBefore, assetsAmountsBefore[0]);
//        console.log("amountAfter", amountAfter, balanceAfter, assetsAmountsAfter[0]);
//        console.log("xSilo price", price);
        console.log("delta usdc", (assetsAmountsAfter[0] - assetsAmountsBefore[0]) / 1e6, expectedAmountUSD);

        assertGt(amountBefore, 0, "There are unclaimed xSilo");
        assertGt(balanceBefore, 0, "There are claimed xSilo on the strategy balance");
        assertEq(amountAfter, 0, "There are NO unclaimed xSilo after hard work");
        assertEq(balanceAfter, 0, "There are NO claimed xSilo on the strategy balance after hard work");
        assertGt(assetsAmountsAfter[0], assetsAmountsBefore[0], "total amount was increased after hard work");
        assertLt(
            _getPositiveDiffPercent4(expectedAmountUSD, (assetsAmountsAfter[0] - assetsAmountsBefore[0]) / 1e6),
            2000,
            "total amount was increased by expected amount"
        );
    }

    //region ------------------------------ Auxiliary Functions
    function _getRewards(address strategy, ISiloVault siloVault, address rewardToken_) internal view returns (uint amountOut) {
        IVaultIncentivesModule vim = IVaultIncentivesModule(siloVault.INCENTIVES_MODULE());
        address[] memory claimingLogics = vim.getAllIncentivesClaimingLogics();

        IIncentivesClaimingLogic logic = IIncentivesClaimingLogic(claimingLogics[0]); // single logic is enough, multiple logics produce duplicates
        ISiloIncentivesControllerForVault c = ISiloIncentivesControllerForVault(logic.VAULT_INCENTIVES_CONTROLLER());

        string[] memory programNames = c.getAllProgramsNames();
        for (uint j; j < programNames.length; ++j) {
            uint unclaimedRewards = c.getRewardsBalance(address(strategy), programNames[j]);
            c.getUserData(address(strategy), programNames[j]);
            (, address rewardToken,,,) = c.incentivesPrograms(c.getProgramId(programNames[j]));
            if (rewardToken == rewardToken_) {
                amountOut += unclaimedRewards;
                // console.log("Unclaimed rewards for", unclaimedRewards, rewardToken_);
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

    function _upgradeRewardAssetsInFarm(address strategy) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        IFarmingStrategy farmingStrategy = IFarmingStrategy(strategy);
        uint farmId = farmingStrategy.farmId();

        IFactory.Farm memory f = factory.farm(farmId);
        f.rewardAssets = new address[](2);
        f.rewardAssets[0] = SonicConstantsLib.TOKEN_SILO;
        f.rewardAssets[1] = SonicConstantsLib.TOKEN_xSILO;

        vm.prank(multisig);
        factory.updateFarm(farmId, f);

        vm.prank(multisig);
        farmingStrategy.refreshFarmingAssets();
    }

    function _addPoolForXSilo() internal {
        IPlatform platform = IPlatform(PLATFORM);
        ISwapper swapper = ISwapper(platform.swapper());

        bytes32 _hash = keccak256(bytes(AmmAdapterIdLib.UNISWAPV3));
        IAmmAdapter adapter = IAmmAdapter(platform.ammAdapter(_hash).proxy);

        ISwapper.PoolData[] memory pools = new ISwapper.PoolData[](1);
//        pools[0] = ISwapper.PoolData({
//            pool: SonicConstantsLib.POOL_SHADOW_CL_x33_xSILO,
//            ammAdapter: address(adapter),
//            tokenIn: SonicConstantsLib.TOKEN_xSILO,
//            tokenOut: SonicConstantsLib.TOKEN_x33
//        });
        pools[0] = ISwapper.PoolData({
            pool: SonicConstantsLib.POOL_SHADOW_CL_xSILO_SILO,
            ammAdapter: address(adapter),
            tokenIn: SonicConstantsLib.TOKEN_xSILO,
            tokenOut: SonicConstantsLib.TOKEN_SILO
        });

        vm.prank(address(multisig));
        swapper.addPools(pools, false);
    }

    function _getPositiveDiffPercent4(uint x, uint y) internal pure returns (uint) {
        return x > y ? (x - y) * 100_00 / x : 0;
    }
    //endregion ------------------------------ Auxiliary Functions
}
