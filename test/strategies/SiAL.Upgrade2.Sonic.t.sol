// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ISilo} from "../../src/integrations/silo/ISilo.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {console, Test} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {SiloAdvancedLeverageStrategy} from "../../src/strategies/SiloAdvancedLeverageStrategy.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";

/// @notice #254: Fix decreasing LTV on exits
contract SiALUpgrade2Test is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    /// @notice #254: LTV is decreasing on exit
    address public constant STRATEGY = 0x636364e3B21B17007E4e0b527F5C345c35064F16; // C-PT-aSonUSDC-14AUG2025-SAL

    /// @notice #247: deposit is not possible because the assets has different decimals
    address public constant STRATEGY2 = 0x61B6A56d9b3BAf6611e6E338B424B57221e6C91B; // C-PT-wstkscUSD-29MAY2025-SAL

    address public constant PT_AAVE_SONIC_USD = 0x930441Aa7Ab17654dF5663781CA0C02CC17e6643; // decimals 6

    address public constant BEETS_VAULT_V3 = 0xbA1333333333a1BA1108E8412f11850A5C319bA9;
    address public constant SHADOW_POOL_FRXUSD_SCUSD = 0xf28c748091FdaB86d5120aB359fCb471dAA6467d;

    uint internal constant FLASH_LOAN_KIND_BALANCER_V3 = 1;
    uint internal constant FLASH_LOAN_KIND_UNISWAP_V3 = 2;

    address public multisig;
    IFactory public factory;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        // vm.rollFork(22987373); // Apr-29-2025 02:42:43 AM +UTC
        vm.rollFork(23744356); // May-02-2025 09:18:23 AM +UTC

        factory = IFactory(IPlatform(PLATFORM).factory());
        multisig = IPlatform(PLATFORM).multisig();
    }

    /// @notice #254
    function testSiALUpgrade1() public {
        console.log("testSiALUpgrade");
        address user1 = address(1);
        // address user2 = address(2);

        // ----------------- deploy new impl and upgrade
        _upgradeStrategy(STRATEGY);

        // ----------------- access to the strategy
        vm.prank(multisig);
        address vault = IStrategy(STRATEGY).vault();
        SiloAdvancedLeverageStrategy strategy = SiloAdvancedLeverageStrategy(payable(STRATEGY));
        vm.stopPrank();

        // ----------------- check current state
        uint ltv = _showHealth(strategy, "!!!Initial state");

        // ----------------- restore LTV to 80%
        console.log("!!!Rebalance to 80%");

        vm.startPrank(multisig);
        strategy.rebalanceDebt(80_00);
        vm.stopPrank();

        ltv = _showHealth(strategy, "!!!After rebalanceDebt");

        assertApproxEqAbs(ltv, 80_00, 1000);

        // ----------------- deposit large amount
//        _depositForUser(vault, address(strategy), user2, 1_000e6);
//        ltv = _showHealth(strategy, "After deposit 2");

        console.log("!!!Deposit");
        _depositForUser(vault, address(strategy), user1, 100_000e6);
        ltv = _showHealth(strategy, "!!!After deposit 1");

        // ----------------- withdraw all
        vm.roll(block.number + 6);
        console.log("!!!Withdraw");
        _withdrawAllForUser(vault, address(strategy), user1);
        ltv = _showHealth(strategy, "!!!After withdraw 1");
    }

    /// @notice #247: decimals 6:18
    function testSiALUpgrade2() public {
        console.log("testSiALUpgrade2");
        address user1 = address(1);
        address user2 = address(2);
        address vault = IStrategy(STRATEGY2).vault();

        // ----------------- deploy new impl and upgrade
        _upgradeStrategy(STRATEGY2);
        _upgradeVault(vault); // todo remove - we need it for console logs only (?)

        // ----------------- access to the strategy
        vm.prank(multisig);
        SiloAdvancedLeverageStrategy strategy = SiloAdvancedLeverageStrategy(payable(STRATEGY2));
        _adjustParams(strategy);
        vm.stopPrank();

        // ----------------- set up free balancer v3 flash loan

        // current flash loand vault is 0xBA12222222228d8Ba445958a75a0704d566BF2C8
        // we need to get Frax USD
        // !TODO _setFlashLoanVault(strategy, BEETS_VAULT_V3, FLASH_LOAN_KIND_BALANCER_V3);
        _setFlashLoanVault(strategy, SHADOW_POOL_FRXUSD_SCUSD, FLASH_LOAN_KIND_UNISWAP_V3);

        // ----------------- check current state
        uint ltv = _showHealth(strategy, "!!!Initial state");

        // ----------------- deposit large amount
        console.log("!!!Deposit user2");
        _depositForUser(vault, address(strategy), user2, 2e6);
        ltv = _showHealth(strategy, "!!!After deposit 2");

        console.log("!!!Deposit user1");
        _depositForUser(vault, address(strategy), user1, 1000e6);
        ltv = _showHealth(strategy, "!!!After deposit 1");

        // ----------------- withdraw all
        vm.roll(block.number + 6);
        console.log("!!!Withdraw user1");
        _withdrawAllForUser(vault, address(strategy), user1);
        ltv = _showHealth(strategy, "!!!After withdraw 1");

        console.log("done");
    }

    /// @notice #247: decimals 18:18
    function testSiALUpgrade3() public {
        console.log("testSiALUpgrade3");
        address user1 = address(1);
        address user2 = address(2);
        address STRATEGY3 = 0x92b36B43CA5beaB1dDA4abfebFb6B6B741bd3859;

        // ----------------- deploy new impl and upgrade
        _upgradeStrategy(STRATEGY3);

        // ----------------- access to the strategy
        vm.prank(multisig);
        address vault = IStrategy(STRATEGY3).vault();
        SiloAdvancedLeverageStrategy strategy = SiloAdvancedLeverageStrategy(payable(STRATEGY3));
        vm.stopPrank();

        // ----------------- check current state
        uint ltv = _showHealth(strategy, "!!!Initial state");

        // ----------------- deposit large amount
        console.log("!!!Deposit user2");
        _depositForUser(vault, address(strategy), user2, 1e18);
        ltv = _showHealth(strategy, "!!!After deposit 2");

        console.log("!!!Deposit user1");
        _depositForUser(vault, address(strategy), user1, 10e18);
        ltv = _showHealth(strategy, "!!!After deposit 1");

        // ----------------- withdraw all
        vm.roll(block.number + 6);
        console.log("!!!Withdraw user1");
        _withdrawAllForUser(vault, address(strategy), user1);
        ltv = _showHealth(strategy, "!!!After withdraw 1");

        console.log("done");
    }

//region -------------------------- Auxiliary functions
    function _showHealth(SiloAdvancedLeverageStrategy strategy, string memory state) internal view returns (uint) {
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

    function _depositForUser(address vault, address strategy, address user, uint depositAmount) internal {
        address[] memory assets = IStrategy(strategy).assets();
        deal(assets[0], user, depositAmount);
        vm.startPrank(user);
        IERC20(assets[0]).approve(vault, depositAmount);
        uint[] memory amounts = new uint[](1);
        amounts[0] = depositAmount;
        IVault(vault).depositAssets(assets, amounts, 0, user);
        vm.stopPrank();
    }

    function _withdrawAllForUser(address vault, address strategy, address user) internal {
        address[] memory assets = IStrategy(strategy).assets();
        uint bal = IERC20(vault).balanceOf(user);
        vm.prank(user);
        IVault(vault).withdrawAssets(assets, bal, new uint[](1));
    }

    function _upgradeStrategy(address strategyAddress) internal {
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

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _upgradeVault(address vaultAddress) internal {
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

        factory.upgradeVaultProxy(vaultAddress);
    }

    function _adjustParams(SiloAdvancedLeverageStrategy strategy) internal {
        uint[] memory params = strategy.getUniversalParams();
        params[0] = 10000;
        vm.prank(multisig);
        strategy.setUniversalParams(params);
    }

    function _setFlashLoanVault(SiloAdvancedLeverageStrategy strategy, address vault, uint kind) internal {
        vm.prank(multisig);
        strategy.setFlashLoanVault(vault, kind);
    }

//endregion -------------------------- Auxiliary functions
}
