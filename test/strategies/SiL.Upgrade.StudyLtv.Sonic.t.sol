// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SiloLeverageStrategy} from "../../src/strategies/SiloLeverageStrategy.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {console, Test} from "forge-std/Test.sol";

contract SiLUpgradeStudyLtvTest is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    /// @notice Stability stS Silo Leverage 3 wS x17.4
    address public constant VAULT = SonicConstantsLib.VAULT_C_wS_Silo_Leverage3_stS_55;

    IVault public vault;
    address public multisig;
    IFactory public factory;
    IPriceReader public priceReader;

    struct State {
        uint ltv;
        uint maxLtv;
        uint leverage;
        uint collateralAmount;
        uint debtAmount;
        uint targetLeveragePercent;
        uint total;
        uint sharePrice;
        uint maxLeverage;
        uint targetLeverage;
        string stateName;
    }

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        // vm.rollFork(34426100); // Jun-17-2025 02:30:51 AM +UTC
        // vm.rollFork(34626742); // Jun-18-2025 07:17:56 AM +UTC
        // vm.rollFork(34631116); // Jun-18-2025 07:59:24 AM +UTC
        vm.rollFork(34686957-1); // Jun-18-2025 03:25:18 PM +UTC

        factory = IFactory(IPlatform(PLATFORM).factory());
        multisig = IPlatform(PLATFORM).multisig();
        vault = IVault(VAULT);
        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
    }

    function testDeposit() public {
        address userHolder = 0xc2024E4bCAb1FFD8281C512F81d3Def0fd357940;

        vm.prank(multisig);
        address strategyAddress = address(vault.strategy());

        // ----------------- deploy new impl and upgrade
        _upgradeStrategy(strategyAddress);

        SiloLeverageStrategy strategy = SiloLeverageStrategy(payable(strategyAddress));
        vm.stopPrank();

        // ----------------- set up
        _adjustParams(strategy);
        _setTargetLeveragePercent(strategy, 8000);

        // ----------------- deposit & withdraw
        State memory stateBefore = _getHealth(address(vault), "!!!Before deposit");
        uint amount = 19116e18;
        _depositForUser(address(vault), userHolder, amount);
        vm.roll(block.number + 6);

        State memory stateAfter = _getHealth(address(vault), "!!!After deposit");
        assertApproxEqAbs(stateBefore.ltv, stateAfter.ltv, 2, "LTV should not change much");
        assertLt(_getDiffPercent4(stateBefore.leverage, stateAfter.leverage), 100, "Leverage should not change much");
    }

    function testWithdraw() public {
        address userHolder = 0xe51f74A17Ff1fc0505488729bD6d5Bd24F8b86f1;

        vm.prank(multisig);
        address strategyAddress = address(vault.strategy());

        // ----------------- deploy new impl and upgrade
        _upgradeStrategy(strategyAddress);
        _upgradeCVaults();

        SiloLeverageStrategy strategy = SiloLeverageStrategy(payable(strategyAddress));
        vm.stopPrank();

        // ----------------- set up
        _adjustParams(strategy);
        _setTargetLeveragePercent(strategy, 8000);

        // ----------------- deposit & withdraw
        uint amount = vault.balanceOf(userHolder);
        (uint tvl,) = vault.tvl();
        (uint assetPrice, ) = priceReader.getPrice(vault.assets()[0]);
        console.log("asset price", assetPrice);

        State memory stateBefore = _getHealth(address(vault), "!!!Before withdraw");
        uint withdrawn = _withdrawForUser(address(vault), strategyAddress, userHolder, amount);
        vm.roll(block.number + 6);

        uint expectedToWithdraw = tvl * amount * 1e18 * 100_00 / vault.totalSupply() / stateBefore.leverage / assetPrice;

        State memory stateAfter = _getHealth(address(vault), "!!!After withdraw");

        assertLt(_getDiffPercent4(withdrawn, expectedToWithdraw), 500, "5% diff is ok");
        assertLt(stateAfter.ltv, stateBefore.ltv, "LTV should decrease after withdraw");
        assertApproxEqAbs(stateBefore.ltv, stateAfter.ltv, 5, "LTV should not change much");
    }

    //region -------------------------- Deposit withdraw routines
    function _depositForUser(address vault_, address user, uint depositAmount) internal returns (uint) {
        address[] memory assets = IStrategy(IVault(vault_).strategy()).assets();

        // --------------------------- provide amount to the user
        deal(assets[0], user, depositAmount + IERC20(assets[0]).balanceOf(user));

        // --------------------------- state before deposit
        _getHealth(vault_, "!!!Before deposit");

        // --------------------------- deposit
        vm.startPrank(user);
        IERC20(assets[0]).approve(vault_, depositAmount);
        uint[] memory amounts = new uint[](1);
        amounts[0] = depositAmount;
        IVault(vault_).depositAssets(assets, amounts, 0, user);
        vm.stopPrank();

        // --------------------------- state after deposit
        _getHealth(vault_, "!!!After deposit");

        // --------------------------- check results
        return depositAmount;
    }

    function _withdrawAllForUser(address vault_, address strategy, address user) internal returns (uint) {
        return _withdrawAmount(vault_, strategy, user, IERC20(vault_).balanceOf(user));
    }

    function _withdrawForUser(address vault_, address strategy, address user, uint amount) internal returns (uint) {
        uint amountToWithdraw = Math.min(amount, IERC20(vault_).balanceOf(user));
        return _withdrawAmount(vault_, strategy, user, amountToWithdraw);
    }

    function _withdrawForUserPartly(
        address vault_,
        address strategy,
        address user,
        uint percent
    ) internal returns (uint) {
        return _withdrawAmount(vault_, strategy, user, IERC20(vault_).balanceOf(user) * percent / 100);
    }

    function _withdrawAmount(address vault_, address strategy, address user, uint amount) internal returns (uint) {
        // --------------------------- state before withdraw
        _getHealth(vault_, "!!!Before withdraw");

        // --------------------------- withdraw
        address[] memory assets = IStrategy(strategy).assets();
        uint balanceBefore = IERC20(assets[0]).balanceOf(user);

        vm.prank(user);
        IVault(vault_).withdrawAssets(assets, amount, new uint[](1));

        // --------------------------- state after withdraw
        _getHealth(vault_, "!!!After withdraw");

        // --------------------------- check results
        return IERC20(assets[0]).balanceOf(user) - balanceBefore;
    }
    //endregion -------------------------- Deposit withdraw routines

    //region -------------------------- Auxiliary functions
    function _getHealth(address vault_, string memory stateName) internal view returns (State memory state) {
        SiloLeverageStrategy strategy = SiloLeverageStrategy(payable(address(IVault(vault_).strategy())));
        // console.log(stateName);

        (state.ltv, state.maxLtv, state.leverage, state.collateralAmount, state.debtAmount, state.targetLeveragePercent)
        = strategy.health();
        state.total = strategy.total();
        (state.sharePrice,) = strategy.realSharePrice();
        state.maxLeverage = 100_00 * 1e18 / (1e18 - state.maxLtv);
        state.stateName = stateName;
        state.targetLeverage = state.maxLeverage * state.targetLeveragePercent / 100_00;
//
//        console.log("ltv", state.ltv);
//        console.log("maxLtv", state.maxLtv);
//        console.log("leverage", state.leverage);
//        console.log("collateralAmount", state.collateralAmount);
//        console.log("debtAmount", state.debtAmount);
//        console.log("targetLeveragePercent", state.targetLeveragePercent);
//        console.log("maxLeverage", state.maxLeverage);
//        console.log("targetLeverage", state.targetLeverage);
        return state;
    }

    function getSharePriceAndTvl(SiloLeverageStrategy strategy) internal view returns (uint sharePrice, uint tvl) {
        (tvl,) = strategy.realTvl();
        (sharePrice,) = strategy.realSharePrice();
    }

    function _upgradeStrategy(address strategyAddress) internal {
        address strategyImplementation = address(new SiloLeverageStrategy());
        vm.prank(multisig);
        factory.setStrategyLogicConfig(
            IFactory.StrategyLogicConfig({
                id: StrategyIdLib.SILO_LEVERAGE,
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

    function _adjustParams(SiloLeverageStrategy strategy) internal {
        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();
//        params[0] = 10000; // depositParam0: use default flash amount
        params[2] = 9950; // 10000; // withdrawParam0: use default flash amount
        params[3] = 0; // withdrawParam1: allow 200% of deposit after withdraw
//        params[11] = 9500; // withdrawParam2: allow withdraw-through-increasing-ltv if leverage < 95% of target level
        vm.prank(multisig);
        strategy.setUniversalParams(params, addresses);
    }

    function _setTargetLeveragePercent(SiloLeverageStrategy strategy, uint newPercent) internal {
        vm.prank(multisig);
        strategy.setTargetLeveragePercent(newPercent);
    }

    /// @notice withdrawParams1 increases withdraw amount (rest is deposited back after withdraw)
    function _setWithdrawParam1(SiloLeverageStrategy strategy, uint withdrawParams1) internal {
        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();
        params[3] = withdrawParams1;
        vm.prank(multisig);
        strategy.setUniversalParams(params, addresses);
    }

    function _getDiffPercent4(uint x, uint y) internal pure returns (uint) {
        return x > y ? (x - y) * 100_00 / x : (y - x) * 100_00 / x;
    }

    function _getPositiveDiffPercent4(uint x, uint y) internal pure returns (uint) {
        return x > y ? (x - y) * 100_00 / x : 0;
    }

    function _upgradeCVaults() internal {
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

        factory.upgradeVaultProxy(VAULT);
    }
    //endregion -------------------------- Auxiliary functions
}
