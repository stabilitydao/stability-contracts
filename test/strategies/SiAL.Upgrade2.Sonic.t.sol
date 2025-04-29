// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {console, Test} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {SiloAdvancedLeverageStrategy} from "../../src/strategies/SiloAdvancedLeverageStrategy.sol";

/// @notice #245: Fix decreasing LTV on exits
contract SiALUpgrade2Test is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;
    address public constant STRATEGY = 0x636364e3B21B17007E4e0b527F5C345c35064F16; // C-PT-aSonUSDC-14AUG2025-SAL
    address public constant PT_AAVE_SONIC_USD = 0x930441Aa7Ab17654dF5663781CA0C02CC17e6643; // decimals 6

    address public vault;
    address public multisig;
    IFactory public factory;
    SiloAdvancedLeverageStrategy strategy;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vm.rollFork(22987373); // Apr-29-2025 02:42:43 AM +UTC

        vault = IStrategy(STRATEGY).vault();
        factory = IFactory(IPlatform(PLATFORM).factory());
        multisig = IPlatform(PLATFORM).multisig();
    }

    function testSiALUpgrade() public {
        address user1 = address(1);
        address user2 = address(2);

        // ----------------- deploy new impl and upgrade
        _upgrade();

        // ----------------- access to the strategy
        vm.prank(multisig);
        strategy = SiloAdvancedLeverageStrategy(payable(STRATEGY));
        vm.stopPrank();

        // ----------------- check current state
        uint ltv = _showHealth("Initial state");

        // ----------------- restore LTV to 80%
        console.log("Rebalance to 80%");

        vm.startPrank(multisig);
        strategy.rebalanceDebt(80_00);
        vm.stopPrank();

        ltv = _showHealth("After rebalanceDebt");

        assertApproxEqAbs(ltv, 80_00, 1000);

        // ----------------- deposit large amount
        _depositForUser(user2, 1_000e6);
        ltv = _showHealth("After deposit 2");

        _depositForUser(user1, 100_000e6);
        ltv = _showHealth("After deposit 1");

        // ----------------- withdraw all
        vm.roll(block.number + 6);
        _withdrawAllForUser(user1);
        ltv = _showHealth("After withdraw 1");

//        _withdrawAllForUser(user2);
//        ltv = _showHealth("After withdraw 2");
    }

//region -------------------------- Auxiliary functions
    function _showHealth(string memory state) internal view returns (uint) {
        console.log(state);
        (uint ltv, uint maxLtv, uint leverage, uint collateralAmount, uint debtAmount, uint targetLeveragePercent) = strategy.health();
        console.log("ltv", ltv);
        console.log("maxLtv", maxLtv);
        console.log("leverage", leverage);
        console.log("collateralAmount", collateralAmount);
        console.log("debtAmount", debtAmount);
        console.log("targetLeveragePercent", targetLeveragePercent);
        console.log("Total amount in strategy", strategy.total());

    return ltv;
    }

    function _depositForUser(address user, uint depositAmount) internal {
        address[] memory assets = IStrategy(STRATEGY).assets();
        deal(assets[0], user, depositAmount);
        vm.startPrank(user);
        IERC20(assets[0]).approve(vault, depositAmount);
        uint[] memory amounts = new uint[](1);
        amounts[0] = depositAmount;
        IVault(vault).depositAssets(assets, amounts, 0, user);
        vm.stopPrank();
    }

    function _withdrawAllForUser(address user) internal {
        address[] memory assets = IStrategy(STRATEGY).assets();
        uint bal = IERC20(vault).balanceOf(user);
        vm.prank(user);
        IVault(vault).withdrawAssets(assets, bal, new uint[](1));
    }

    function _deposit(uint depositAmount) internal {
        address[] memory assets = IStrategy(STRATEGY).assets();
        deal(assets[0], address(this), depositAmount);
        IERC20(assets[0]).approve(vault, depositAmount);
        uint[] memory amounts = new uint[](1);
        amounts[0] = depositAmount;
        IVault(vault).depositAssets(assets, amounts, 0, address(this));
    }

    function _upgrade() internal {
        address strategyImplementation = address(new SiloAdvancedLeverageStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.SILO_ADVANCED_LEVERAGE,
                implementation: strategyImplementation,
                deployAllowed: true,
                upgradeAllowed: true,
                farming: true,
                tokenId: 0
            }),
            address(this)
        );

        factory.upgradeStrategyProxy(STRATEGY);
    }
//endregion -------------------------- Auxiliary functions
}
