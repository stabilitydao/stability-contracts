// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AvalancheSetup} from "../base/chains/AvalancheSetup.sol";
import {console, Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
import {AvalancheConstantsLib} from "../../chains/avalanche/AvalancheConstantsLib.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IFarmingStrategy} from "../../src/interfaces/IFarmingStrategy.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {IEVC, IEthereumVaultConnector} from "../../src/integrations/euler/IEthereumVaultConnector.sol";
import {IEulerVault} from "../../src/integrations/euler/IEulerVault.sol";
import {EMFLib} from "../../src/strategies/libs/EMFLib.sol";

contract EulerMerklFarmStrategyTestAvalanche is AvalancheSetup, UniversalTest {
    uint public constant FORK_BLOCK_C_CHAIN = 68407132; // Sep-8-2025 09:54:05 UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("AVALANCHE_RPC_URL"), FORK_BLOCK_C_CHAIN));
        makePoolVolumePriceImpactTolerance = 9_000;
    }

    function testEMF() public universalTest {
        _addStrategy(0);
        _addStrategy(1);
        _addStrategy(2);
        _addStrategy(3);
    }

    //region -------------------------------- Universal test overrides
    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.EULER_MERKL_FARM,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }

    function _preHardWork() internal override {
        // emulate rewards receiving (workaround difficulties with merkl claiming)

        address eulerVaultForStrategy = address(_getEulerVaultForCurrentStrategy());
        if (
            eulerVaultForStrategy == AvalancheConstantsLib.EULER_VAULT_USDC_RE7
            || eulerVaultForStrategy == AvalancheConstantsLib.EULER_VAULT_USDT_K3
        ) {
            deal(AvalancheConstantsLib.TOKEN_WAVAX, currentStrategy, 10e18);
        }

        if (
            eulerVaultForStrategy == AvalancheConstantsLib.EULER_VAULT_BTCB_RESERVOIR
            || eulerVaultForStrategy == AvalancheConstantsLib.EULER_VAULT_WBTC_RESERVOIR
        ) {
            deal(AvalancheConstantsLib.TOKEN_REUL, currentStrategy, 10e18);
        }

    }
    //endregion -------------------------------- Universal test overrides

    //region -------------------------------- Internal logic

    function _tryToDepositToVault(
        address vault,
        uint[] memory amounts_,
        address user,
        bool success
    ) internal returns (uint deposited, uint values) {
        address[] memory assets = IVault(vault).assets();
        // ----------------------------- Prepare amount on user's balance
        _dealAndApprove(user, vault, assets, amounts_);
        // console.log("Deposit to vault", assets[0], amounts_[0]);

        // ----------------------------- Try to deposit assets to the vault
        uint valuesBefore = IERC20(vault).balanceOf(user);

        if (!success) {
            vm.expectRevert();
        }
        vm.prank(user);
        IStabilityVault(vault).depositAssets(assets, amounts_, 0, user);

        vm.roll(block.number + 6);

        return (amounts_[0], IERC20(vault).balanceOf(user) - valuesBefore);
    }

    function _getEulerVaultForCurrentStrategy() internal view returns (IEulerVault) {
        IPlatform _platform = IPlatform(IControllable(currentStrategy).platform());
        uint farmId = IFarmingStrategy(currentStrategy).farmId();
        IFactory.Farm memory farm = IFactory(_platform.factory()).farm(farmId);
        return IEulerVault(farm.addresses[1]);
    }
    //endregion -------------------------------- Internal logic

    //region --------------------------------- Helpers
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
    //endregion --------------------------------- Helpers
}
