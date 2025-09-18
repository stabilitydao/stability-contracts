// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/console.sol";
import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
import {SonicLib, SonicConstantsLib} from "../../chains/sonic/SonicLib.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {ISiloVault} from "../../src/integrations/silo/ISiloVault.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IFarmingStrategy} from "../../src/interfaces/IFarmingStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";

contract SiloManagedMerklFarmStrategySonicTest is SonicSetup, UniversalTest {
    uint private constant FORK_BLOCK = 47005295; // Sep-16-2025 05:50:01 AM +UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(FORK_BLOCK);
    }

    function testSiMMFSonic() public universalTest {
        _addStrategy(64);
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO_MANAGED_MERKL_FARM,
                pool: address(0),
                farmId: farmId, // chains/sonic/SonicLib.sol
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }

    //region -------------------------------- Universal test overrides
    function _preHardWork() internal override {
        // emulate Merkl-rewards
        deal(SonicConstantsLib.TOKEN_USDC, currentStrategy, 1e6);
        deal(SonicConstantsLib.TOKEN_XSILO, currentStrategy, 100e18);
        deal(SonicConstantsLib.TOKEN_SILO, currentStrategy, 100e18);
    }

    /// @notice Try to deposit and ensure that poolTvl is changed correctly
    function _checkPoolTvl() internal override returns (bool) {
        uint snapshotId = vm.snapshotState();
        IStrategy _strategy = IStrategy(currentStrategy);
        IStabilityVault _vault = IStabilityVault(_strategy.vault());
        ISiloVault siloVault = ISiloVault(_getSiloVaultForCurrentStrategy());

        // --------------------- State before deposit
        uint cashBefore = siloVault.totalAssets();
        uint tvlUsdBefore = _strategy.poolTvl();

        // --------------------- Deposit to the strategy
        uint[] memory amountsToDeposit = new uint[](1);
        amountsToDeposit[0] = cashBefore / 1000;
        (uint deposited,) = _tryToDepositToVault(_strategy.vault(), amountsToDeposit, address(this), true);

        (uint priceAsset,) = IPriceReader(IPlatform(IControllable(currentStrategy).platform()).priceReader()).getPrice(
            _vault.assets()[0]
        );

        uint cashAfter = siloVault.totalAssets();
        uint tvlUsdAfter = _strategy.poolTvl();

        // --------------------- Check poolTvl values
        assertApproxEqAbs(
            cashAfter, cashBefore + deposited, 1, "Silo totalAsset should be increased on deposited amount"
        );
        assertApproxEqAbs(
            tvlUsdAfter,
            tvlUsdBefore + deposited * priceAsset / (10 ** IERC20Metadata(siloVault.asset()).decimals()),
            1,
            "TVL should increase on deposited amount"
        );

        vm.revertToState(snapshotId);

        return super._checkPoolTvl();
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

    //endregion -------------------------------- Internal logic

    //region -------------------------------- Utils
    function _getSiloVaultForCurrentStrategy() internal view returns (address) {
        IPlatform _platform = IPlatform(IControllable(currentStrategy).platform());
        uint farmId = IFarmingStrategy(currentStrategy).farmId();
        IFactory.Farm memory farm = IFactory(_platform.factory()).farm(farmId);
        return farm.addresses[0];
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
    //endregion -------------------------------- Utils
}
