// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ISiloIncentivesControllerForVault} from "../../src/integrations/silo/ISiloIncentivesControllerForVault.sol";
import {IBalancerGauge} from "../../src/integrations/balancer/IBalancerGauge.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IGaugeEquivalent} from "../../src/integrations/equalizer/IGaugeEquivalent.sol";
import {IGaugeV2_CL} from "../../src/integrations/swapx/IGaugeV2_CL.sol";
import {IGaugeV2} from "../../src/integrations/swapx/IGaugeV2.sol";
import {IGaugeV3} from "../../src/integrations/shadow/IGaugeV3.sol";
import {IHypervisor} from "../../src/integrations/gamma/IHypervisor.sol";
import {IICHIVault} from "../../src/integrations/ichi/IICHIVault.sol";
import {IIncentivesClaimingLogic} from "../../src/integrations/silo/IIncentivesClaimingLogic.sol";
import {ISiloIncentivesController} from "../../src/integrations/silo/ISiloIncentivesController.sol";
import {ISiloVault} from "../../src/integrations/silo/ISiloVault.sol";
import {IVaultIncentivesModule} from "../../src/integrations/silo/IVaultIncentivesModule.sol";
import {SonicConstantsLib} from "./SonicConstantsLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";

/// @author Jude (https://github.com/iammrjude)
library SonicFarmMakerLib {
    function _makeALMShadowFarm(
        address gauge,
        uint algoId,
        int24 range,
        int24 triggerRange
    ) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IGaugeV3(gauge).pool();
        farm.strategyLogicId = StrategyIdLib.ALM_SHADOW_FARM;
        farm.rewardAssets = IGaugeV3(gauge).getRewardTokens();
        farm.addresses = new address[](3);
        farm.addresses[0] = gauge;
        farm.addresses[1] = IGaugeV3(gauge).nfpManager();
        farm.addresses[2] = SonicConstantsLib.TOKEN_xSHADOW;
        farm.nums = new uint[](1);
        farm.nums[0] = algoId;
        farm.ticks = new int24[](2);
        farm.ticks[0] = range;
        farm.ticks[1] = triggerRange;
        return farm;
    }

    function _makeGammaUniswapV3MerklFarm(
        address hypervisor,
        uint preset,
        address rewardAsset
    ) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IHypervisor(hypervisor).pool();
        farm.strategyLogicId = StrategyIdLib.GAMMA_UNISWAPV3_MERKL_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = rewardAsset;
        farm.addresses = new address[](2);
        farm.addresses[0] = SonicConstantsLib.GAMMA_UNISWAPV3_UNIPROXY;
        farm.addresses[1] = hypervisor;
        farm.nums = new uint[](1);
        farm.nums[0] = preset;
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeGammaEqualizerFarm(
        address hypervisor,
        uint preset,
        address gauge
    ) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IHypervisor(hypervisor).pool();
        farm.strategyLogicId = StrategyIdLib.GAMMA_EQUALIZER_FARM;
        uint len = IGaugeEquivalent(gauge).rewardsListLength();
        farm.rewardAssets = new address[](len);
        for (uint i; i < len; ++i) {
            farm.rewardAssets[i] = IGaugeEquivalent(gauge).rewardTokens(i);
        }
        farm.addresses = new address[](3);
        farm.addresses[0] = SonicConstantsLib.GAMMA_EQUALIZER_UNIPROXY;
        farm.addresses[1] = hypervisor;
        farm.addresses[2] = gauge;
        farm.nums = new uint[](1);
        farm.nums[0] = preset;
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeSwapXFarm(address gauge) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IGaugeV2(gauge).TOKEN();
        farm.strategyLogicId = StrategyIdLib.SWAPX_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = IGaugeV2(gauge).rewardToken();
        farm.addresses = new address[](2);
        farm.addresses[0] = gauge;
        farm.addresses[1] = SonicConstantsLib.SWAPX_ROUTER_V2;
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeIchiSwapXFarm(address gauge) internal view returns (IFactory.Farm memory) {
        address alm = IGaugeV2_CL(gauge).TOKEN();
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IICHIVault(alm).pool();
        farm.strategyLogicId = StrategyIdLib.ICHI_SWAPX_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = IGaugeV2_CL(gauge).rewardToken();
        farm.addresses = new address[](2);
        farm.addresses[0] = alm;
        farm.addresses[1] = gauge;
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeIchiEqualizerFarm(
        address vault,
        address gauge
    ) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IICHIVault(vault).pool();
        farm.strategyLogicId = StrategyIdLib.ICHI_EQUALIZER_FARM;
        uint len = IGaugeEquivalent(gauge).rewardsListLength();
        farm.rewardAssets = new address[](len);
        for (uint i; i < len; ++i) {
            farm.rewardAssets[i] = IGaugeEquivalent(gauge).rewardTokens(i);
        }
        farm.addresses = new address[](2);
        farm.addresses[0] = vault;
        farm.addresses[1] = gauge;
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeBeetsStableFarm(address gauge) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IBalancerGauge(gauge).lp_token();
        farm.strategyLogicId = StrategyIdLib.BEETS_STABLE_FARM;
        uint len = IBalancerGauge(gauge).reward_count();
        farm.rewardAssets = new address[](len);
        for (uint i; i < len; ++i) {
            farm.rewardAssets[i] = IBalancerGauge(gauge).reward_tokens(i);
        }
        farm.addresses = new address[](1);
        farm.addresses[0] = gauge;
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeBeetsWeightedFarm(address gauge) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IBalancerGauge(gauge).lp_token();
        farm.strategyLogicId = StrategyIdLib.BEETS_WEIGHTED_FARM;
        uint len = IBalancerGauge(gauge).reward_count();
        farm.rewardAssets = new address[](len);
        for (uint i; i < len; ++i) {
            farm.rewardAssets[i] = IBalancerGauge(gauge).reward_tokens(i);
        }
        farm.addresses = new address[](1);
        farm.addresses[0] = gauge;
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeEqualizerFarm(address gauge) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.pool = IGaugeEquivalent(gauge).stake();
        farm.strategyLogicId = StrategyIdLib.EQUALIZER_FARM;
        uint len = IGaugeEquivalent(gauge).rewardsListLength();
        farm.rewardAssets = new address[](len);
        for (uint i; i < len; ++i) {
            farm.rewardAssets[i] = IGaugeEquivalent(gauge).rewardTokens(i);
        }
        farm.addresses = new address[](2);
        farm.addresses[0] = gauge;
        farm.addresses[1] = SonicConstantsLib.EQUALIZER_ROUTER_03;
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    function _makeSiloFarm(address gauge) internal view returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.strategyLogicId = StrategyIdLib.SILO_FARM;
        farm.rewardAssets = new address[](1);
        farm.rewardAssets[0] = SonicConstantsLib.TOKEN_wS;
        farm.addresses = new address[](2);
        farm.addresses[0] = gauge;
        farm.addresses[1] = ISiloIncentivesController(gauge).SHARE_TOKEN();
        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

    function _getSiloManagedFarmRewards(address managedVault) internal view returns (address[] memory rewardAssets) {
        IVaultIncentivesModule vim = IVaultIncentivesModule(ISiloVault(managedVault).INCENTIVES_MODULE());
        address[] memory claimingLogics = vim.getAllIncentivesClaimingLogics();

        // get max possible amounts of rewards
        uint len;
        for (uint i; i < claimingLogics.length; ++i) {
            IIncentivesClaimingLogic logic = IIncentivesClaimingLogic(claimingLogics[i]);
            ISiloIncentivesControllerForVault c = ISiloIncentivesControllerForVault(logic.VAULT_INCENTIVES_CONTROLLER());
            string[] memory programsNames = c.getAllProgramsNames();
            len += programsNames.length;
        }

        // generate list of rewards without duplicates but probably with zero addresses
        address[] memory temp = new address[](len);
        len = 0;
        for (uint i; i < claimingLogics.length; ++i) {
            IIncentivesClaimingLogic logic = IIncentivesClaimingLogic(claimingLogics[i]);
            ISiloIncentivesControllerForVault c = ISiloIncentivesControllerForVault(logic.VAULT_INCENTIVES_CONTROLLER());
            string[] memory programsNames = c.getAllProgramsNames();
            for (uint j; j < programsNames.length; ++j) {
                bytes32 programId = c.getProgramId(programsNames[j]);
                (, address rewardToken,,,) = c.incentivesPrograms(programId);
                if (rewardToken != address(0)) {
                    bool found;
                    for (uint k; k < len; k++) {
                        if (temp[k] == rewardToken) {
                            found = true;
                        }
                    }
                    if (! found) {
                        temp[len++] = rewardToken;
                    }
                }
            }
        }

        // temp => farm.rewardAssets, cut zero addresses
        rewardAssets = new address[](len);
        for (uint i; i < len; ++i) {
            rewardAssets[i] = temp[i];
        }

        return rewardAssets;
    }

    function _makeSiloManagedFarm(address managedVault) internal pure returns (IFactory.Farm memory) {
        IFactory.Farm memory farm;
        farm.status = 0;
        farm.strategyLogicId = StrategyIdLib.SILO_MANAGED_FARM;

        // we can use getSiloManagedFarmRewards to auto-detect reward assets
        // but some vaults return empty array (probably it's not empty on other blocks)
        farm.rewardAssets = new address[](4);
        farm.rewardAssets[0] = SonicConstantsLib.TOKEN_SILO;
        farm.rewardAssets[1] = SonicConstantsLib.TOKEN_wS;
        farm.rewardAssets[2] = SonicConstantsLib.TOKEN_wOS;
        farm.rewardAssets[3] = SonicConstantsLib.TOKEN_beS;

        farm.addresses = new address[](1);
        farm.addresses[0] = managedVault;

        farm.nums = new uint[](0);
        farm.ticks = new int24[](0);
        return farm;
    }

}