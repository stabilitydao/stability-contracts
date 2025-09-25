// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {UniversalTest} from "../base/UniversalTest.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";

contract SiloAdvancedLeverageStrategyTest is SonicSetup, UniversalTest {
    constructor() {
        //vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        //vm.rollFork(11356000); // Mar-03-2025 08:19:49 AM +UTC
        //vm.rollFork(13119000); // Mar-11-2025 08:29:09 PM +UTC
        // vm.rollFork(18553912); // Apr-01-2025 03:26:51 PM +UTC
        // vm.rollFork(24454255); // May-05-2025 06:57:40 AM +UTC
        // vm.rollFork(25224612); // May-08-2025 10:18:00 AM +UTC
        // vm.rollFork(26428190); // May-13-2025 06:22:27 AM +UTC
        // vm.rollFork(27167657); // May-16-2025 06:25:41 AM +UTC
        // vm.rollFork(28965600); // May-23-2025 08:48:26 AM +UTC
        vm.rollFork(47749273); // Sep-22-2025 08:07:18 AM +UTC
        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;
    }

    function testSiALSonic() public universalTest {
        //                _addStrategy(SonicConstantsLib.SILO_VAULT_22_WOS, SonicConstantsLib.SILO_VAULT_22_WS, 86_90);
        //                _addStrategy(SonicConstantsLib.SILO_VAULT_23_WSTKSCUSD, SonicConstantsLib.SILO_VAULT_23_USDC, 88_00);
        //                         _addStrategy(SonicConstantsLib.SILO_VAULT_26_WSTKSCETH, SonicConstantsLib.SILO_VAULT_26_WETH, 90_00);
        //                         _addStrategy(SonicConstantsLib.SILO_VAULT_25_WANS, SonicConstantsLib.SILO_VAULT_25_WS, 90_00);
        //        _addStrategy(SonicConstantsLib.SILO_VAULT_46_PT_AUSDC_14AUG, SonicConstantsLib.SILO_VAULT_46_SCUSD, 60_00);
        //        _addStrategy(SonicConstantsLib.SILO_VAULT_40_PT_STS_29MAY, SonicConstantsLib.SILO_VAULT_40_WS, 65_00);
        //                _addStrategy(SonicConstantsLib.SILO_VAULT_37_PT_WSTKSCUSD_29MAY, SonicConstantsLib.SILO_VAULT_37_FRXUSD, 65_00);

        //        // -------------------------- #295: new vaults 102, 103, 104, 95
        //        // max ltv = 90%, liquidation threshold = 95% => max leverage = 10
        //        _addStrategy(SonicConstantsLib.SILO_VAULT_102_PT_bscUSD_14AUG, SonicConstantsLib.SILO_VAULT_102_USDC, 85_00);
        //        // max ltv = 92%, liquidation threshold = 95% => max leverage = 12.5
        //        _addStrategy(SonicConstantsLib.SILO_VAULT_103_PT_aUSDC_14AUG, SonicConstantsLib.SILO_VAULT_103_USDC, 87_00);
        //        // max ltv = 92%, liquidation threshold = 95% => max leverage = 12.5
        //        _addStrategy(SonicConstantsLib.SILO_VAULT_104_PT_bUSDC_17JUL, SonicConstantsLib.SILO_VAULT_104_USDC, 87_00);
        //        // max ltv = 90%, liquidation threshold = 95% => max leverage = 10
        //        _addStrategy(SonicConstantsLib.SILO_VAULT_54_wOS, SonicConstantsLib.SILO_VAULT_54_S, 85_00);

        // max ltv = 87%, liquidation threshold = 90% => max leverage = 1/(1-0.9) = 10
        _addStrategy(SonicConstantsLib.SILO_VAULT_141_PT_SMSUSD_30OCT2025, SonicConstantsLib.SILO_VAULT_141_USDC, 85_00);

        // max ltv = 87%, liquidation threshold = 90% => max leverage = 1/(1-0.9) = 10
        _addStrategy(SonicConstantsLib.SILO_VAULT_138_SMSUSD, SonicConstantsLib.SILO_VAULT_138_USDC, 85_00);
    }

    function _addStrategy(
        address strategyInitAddress0,
        address strategyInitAddress1,
        uint targetLeveragePercent
    ) internal {
        address[] memory initStrategyAddresses = new address[](4);
        initStrategyAddresses[0] = strategyInitAddress0;
        initStrategyAddresses[1] = strategyInitAddress1;
        initStrategyAddresses[2] = SonicConstantsLib.BEETS_VAULT;
        initStrategyAddresses[3] = SonicConstantsLib.SILO_LENS;
        uint[] memory strategyInitNums = new uint[](1);
        strategyInitNums[0] = targetLeveragePercent;
        strategies.push(
            Strategy({
                id: StrategyIdLib.SILO_ADVANCED_LEVERAGE,
                pool: address(0),
                farmId: type(uint).max,
                strategyInitAddresses: initStrategyAddresses,
                strategyInitNums: strategyInitNums
            })
        );
    }

    /// @notice #330: check maxDepositAssets for SiloAdvancedLeverageStrategy
    function _preDeposit() internal view override {
        IStrategy currentStrategy = IStrategy(currentStrategy);
        IVault vault = IVault(currentStrategy.vault());
        uint[] memory amounts = vault.maxDeposit(address(this));

        assertEq(amounts.length, 1, "SiloAdvancedLeverageStrategyTest: maxDepositAssets length mismatch");
        assertEq(amounts[0], type(uint).max, "SiloAdvancedLeverageStrategyTest: maxDepositAssets should be unlimited");
    }
}
