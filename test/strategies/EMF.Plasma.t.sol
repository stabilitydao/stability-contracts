// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {PlasmaSetup} from "../base/chains/PlasmaSetup.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IFarmingStrategy} from "../../src/interfaces/IFarmingStrategy.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {IEulerVault} from "../../src/integrations/euler/IEulerVault.sol";

contract EulerMerklFarmStrategyPlasmaTest is PlasmaSetup, UniversalTest {
    uint public constant FORK_BLOCK = 2196726; // Sep-29-2025 06:05:08 UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("PLASMA_RPC_URL"), FORK_BLOCK));
        makePoolVolumePriceImpactTolerance = 9_000;
    }

    function testEMF() public universalTest {
        //        _addStrategy(0);
        //        _addStrategy(1);
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
            eulerVaultForStrategy == PlasmaConstantsLib.EULER_MERKL_USDT0_K3_CAPITAL
                || eulerVaultForStrategy == PlasmaConstantsLib.EULER_MERKL_USDT0_RE7
        ) {
            deal(PlasmaConstantsLib.TOKEN_WXPL, currentStrategy, 33e18);
        }

        //        if (
        //            eulerVaultForStrategy == PlasmaConstantsLib.EULER_VAULT_BTCB_RESERVOIR
        //                || eulerVaultForStrategy == PlasmaConstantsLib.EULER_VAULT_WBTC_RESERVOIR
        //        ) {
        //            deal(PlasmaConstantsLib.TOKEN_REUL, currentStrategy, 33e18);
        //        }
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
