// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console, Test} from "forge-std/Test.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {SiloLeverageStrategy} from "../../src/strategies/SiloLeverageStrategy.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract SiLUpgradeTest2 is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    /// @notice Stability stS Silo Leverage 3 wS x17.4
    address public constant VAULT1 = 0x709833e5B4B98aAb812d175510F94Bc91CFABD89;

    /// @notice Stability wS Silo Leverage 3 stS x17.4
    address public constant VAULT2 = 0x2fBeBA931563feAAB73e8C66d7499c49c8AdA224;

    address public constant BALANCER_VAULT_V2 = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant BEETS_VAULT_V3 = 0xbA1333333333a1BA1108E8412f11850A5C319bA9;

    address public constant SHADOW_POOL_S_STS = 0xde861c8Fc9AB78fE00490C5a38813D26e2d09C95;

    uint internal constant FLASH_LOAN_KIND_BALANCER_V3 = 1;
    uint internal constant FLASH_LOAN_KIND_UNISWAP_V3 = 2;

    address public constant ALGEBRA_WS_USDC_POOL = 0x5C4B7d607aAF7B5CDE9F09b5F03Cf3b5c923AEEa;
    address public constant ALGEBRA_USDC_STS_POOL = 0x5DDbeF774488cc68266d5F15bFB08eaA7cd513F9;

    address public multisig;
    IFactory public factory;

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
        // vm.rollFork(16296000); // Mar-27-2025 08:48:46 AM +UTC
        // vm.rollFork(25503966); // May-09-2025 12:31:34 PM +UTC
        // vm.rollFork(26185073); // May-12-2025 07:02:55 AM +UTC
        vm.rollFork(27167657); // May-16-2025 06:25:41 AM +UTC

        factory = IFactory(IPlatform(PLATFORM).factory());
        multisig = IPlatform(PLATFORM).multisig();
    }

    //region -------------------------- Use various flash loan vaults
    /// @notice Check flash loan through Balancer v2
    function testSiLUpgradeBalancerV2() public {
        address user1 = address(1);

        vm.prank(multisig);
        address vault = VAULT2;
        address strategyAddress = address(IVault(vault).strategy());

        uint amount = 10_000e18;

        // ----------------- deploy new impl and upgrade
        _upgradeStrategy(strategyAddress);
        vm.stopPrank();

        // ----------------- use flash loan through Balancer v2
        _setFlashLoanVault(
            SiloLeverageStrategy(payable(strategyAddress)),
            BALANCER_VAULT_V2,
            address(0),
            uint(ILeverageLendingStrategy.FlashLoanKind.Default_0)
        );

        // ----------------- check current state
        address collateralAsset = IStrategy(strategyAddress).assets()[0];

        // ----------------- deposit & withdraw
        _depositForUser(vault, user1, amount);
        vm.roll(block.number + 6);

        _withdrawAllForUser(vault, strategyAddress, user1);
        vm.roll(block.number + 6);


        // ----------------- check results
        console.log(_getDiffPercent4(IERC20(collateralAsset).balanceOf(user1), amount));
        assertLe(_getDiffPercent4(IERC20(collateralAsset).balanceOf(user1), amount), 200); // 2%
    }

    /// @notice Check flash loan through BEETS
    function testSiLUpgradeBalancerV3() public {
        // collateral asset: 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38 // wS
        // borrow asset: 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955 // stS
        address user1 = address(1);

        vm.prank(multisig);
        address vault = VAULT2;
        address strategyAddress = address(IVault(vault).strategy());
        uint amount = 100e18;

        // ----------------- deploy new impl and upgrade
        _upgradeStrategy(strategyAddress);

        SiloLeverageStrategy strategy = SiloLeverageStrategy(payable(strategyAddress));
        vm.stopPrank();

        // ----------------- use flash loan through Balancer v3
        _setFlashLoanVault(
            strategy,
            BEETS_VAULT_V3,
            address(0),
            uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1)
        );

        // ----------------- check current state
        address collateralAsset = IStrategy(strategyAddress).assets()[0];

        // ----------------- deposit & withdraw
        _depositForUser(vault, user1, amount);
        vm.roll(block.number + 6);
        _withdrawAllForUser(vault, strategyAddress, user1);

        // ----------------- check results
        console.log(_getDiffPercent4(IERC20(collateralAsset).balanceOf(user1), amount));
        assertLe(_getDiffPercent4(IERC20(collateralAsset).balanceOf(user1), amount), 200); // 2%
    }

    /// @notice Check flash loan through Uniswap
    function testSiLUpgradeUniswapV3() public {
        // collateral asset: 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38 // wS
        // borrow asset: 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955 // stS
        address user1 = address(1);

        vm.prank(multisig);
        address vault = VAULT1;
        address strategyAddress = address(IVault(vault).strategy());
        // uint amount = 1_00e18;
        uint amount = 100e18;

        // ----------------- deploy new impl and upgrade
        _upgradeStrategy(strategyAddress);

        SiloLeverageStrategy strategy = SiloLeverageStrategy(payable(strategyAddress));
        vm.stopPrank();

        // ----------------- use flash loan through Uniswap V3
        _setFlashLoanVault(
            strategy,
            SHADOW_POOL_S_STS,
            address(0),
            uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2)
        );

        // ----------------- check current state
        address collateralAsset = IStrategy(strategyAddress).assets()[0];

        // ----------------- deposit & withdraw
        _depositForUser(vault, user1, amount);
        vm.roll(block.number + 6);
        _withdrawAllForUser(vault, strategyAddress, user1);

        // ----------------- check results
        console.log(_getDiffPercent4(IERC20(collateralAsset).balanceOf(user1), amount));
        assertLe(_getDiffPercent4(IERC20(collateralAsset).balanceOf(user1), amount), 200); // 2%
    }

    /// @notice Check flash loan through Algebra v4, use two different pools
    function testSiLUpgradeAlgebraV4TwoPools() public {
        // collateral asset: 0x039e2fB66102314Ce7b64Ce5Ce3E5183bc94aD38 // wS
        // borrow asset: 0xE5DA20F15420aD15DE0fa650600aFc998bbE3955 // stS
        address user1 = address(1);

        vm.prank(multisig);
        address vault = VAULT2;
        address strategyAddress = address(IVault(vault).strategy());
        // uint amount = 1_00e18;
        uint amount = 10_000e18;

        // ----------------- deploy new impl and upgrade
        _upgradeStrategy(strategyAddress);

        SiloLeverageStrategy strategy = SiloLeverageStrategy(payable(strategyAddress));
        vm.stopPrank();

        // ----------------- use flash loan through Uniswap V3
        _setFlashLoanVault(
            strategy,
            ALGEBRA_WS_USDC_POOL,
            ALGEBRA_USDC_STS_POOL,
            uint(ILeverageLendingStrategy.FlashLoanKind.AlgebraV4_3)
        );

        // ----------------- check current state
        address collateralAsset = IStrategy(strategyAddress).assets()[0];

        // ----------------- deposit & withdraw
        _depositForUser(vault, user1, amount);
        vm.roll(block.number + 6);
        _withdrawAllForUser(vault, strategyAddress, user1);

        // ----------------- check results
        console.log(_getDiffPercent4(IERC20(collateralAsset).balanceOf(user1), amount));
        assertLe(_getDiffPercent4(IERC20(collateralAsset).balanceOf(user1), amount), 200); // 2%
    }
    //endregion -------------------------- Use various flash loan vaults

    //region -------------------------- Deposit and withdrawAll
    /// @notice Multiple deposit + withdraw all, single user
    function testSiLUpgradeSingleDepositWithdrawAllSingleUser() public {
        address user1 = address(1);

        vm.prank(multisig);
        address vault = VAULT2;
        address strategyAddress = address(IVault(vault).strategy());

        uint amount = 10_000e18;

        // ----------------- deploy new impl and upgrade
        _upgradeStrategy(strategyAddress);

        SiloLeverageStrategy strategy = SiloLeverageStrategy(payable(strategyAddress));
        vm.stopPrank();

        // ----------------- set up
        _setFlashLoanVault(
            strategy,
            SHADOW_POOL_S_STS,
            address(0),
            uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2)
        );

        _adjustParams(strategy);

        // ----------------- deposit & withdraw
        uint deposited = _depositForUser(vault, user1, amount);
        vm.roll(block.number + 6);

        // _withdrawForUser(vault, strategyAddress, user1, amount);
        uint withdrawn = _withdrawAllForUser(vault, strategyAddress, user1);
        vm.roll(block.number + 6);

        // ----------------- check results
        assertLe(_getDiffPercent4(deposited, withdrawn), 100, "deposited ~ withdrawn"); // 1%
    }

    /// @notice Multiple deposit + withdraw all, single user
    function testSiLUpgradeMultipleDepositWithdrawAllSingleUser() public {
        address user1 = address(1);

        vm.prank(multisig);
        address vault = VAULT2;
        address strategyAddress = address(IVault(vault).strategy());

        uint amount = 10_000e18;
        uint COUNT = 20;

        // ----------------- deploy new impl and upgrade
        _upgradeStrategy(strategyAddress);

        SiloLeverageStrategy strategy = SiloLeverageStrategy(payable(strategyAddress));
        vm.stopPrank();

        // ----------------- set up
        _setFlashLoanVault(
            strategy,
            SHADOW_POOL_S_STS,
            address(0),
            uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2)
        );

        _adjustParams(strategy);

        // ----------------- main logic


        for (uint i = 0; i < COUNT; ++i) {
            // ----------------- deposit & withdraw
            uint deposited = _depositForUser(vault, user1, amount);
            vm.roll(block.number + 6);

            // _withdrawForUser(vault, strategyAddress, user1, amount);
            uint withdrawn = _withdrawAllForUser(vault, strategyAddress, user1);
            vm.roll(block.number + 6);

            // ----------------- check results
            assertLe(_getDiffPercent4(deposited, withdrawn), 550, "deposited ~ withdrawn"); // 5.5%

            // ----------------- change amount
            if (i % 2 == 0) {
                amount = amount * 31419/10000;
            } else {
                amount = amount / 3;
            }
        }
    }

    /// @notice Multiple deposit + withdraw all, two users
    function testSiLUpgradeMultipleDepositWithdrawAllTwoUsers() public {
        address user1 = address(1);
        address user2 = address(2);

        vm.prank(multisig);
        address vault = VAULT2;
        address strategyAddress = address(IVault(vault).strategy());

        uint amount1 = 10_000e18;
        uint amount2 = 1_000e18;
        uint COUNT = 10;

        // ----------------- deploy new impl and upgrade
        _upgradeStrategy(strategyAddress);

        SiloLeverageStrategy strategy = SiloLeverageStrategy(payable(strategyAddress));
        vm.stopPrank();

        // ----------------- set up
//        _setFlashLoanVault(
//            strategy,
//            SHADOW_POOL_S_STS,
//            address(0),
//            uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2)
//        );

        _setFlashLoanVault(
            strategy,
            ALGEBRA_WS_USDC_POOL,
            ALGEBRA_USDC_STS_POOL,
            uint(ILeverageLendingStrategy.FlashLoanKind.AlgebraV4_3)
        );

        _adjustParams(strategy);

        // ----------------- main logic


        for (uint i = 0; i < COUNT; ++i) {
            // console.log("*****************************************************", i);
            // ----------------- deposit & withdraw
            uint deposited1 = _depositForUser(vault, user1, amount1);
            vm.roll(block.number + 6);

            uint deposited2 = _depositForUser(vault, user2, amount2);
            vm.roll(block.number + 6);

            // _withdrawForUser(vault, strategyAddress, user1, amount);
            uint withdrawn1 = _withdrawAllForUser(vault, strategyAddress, user1);
            vm.roll(block.number + 6);

            uint withdrawn2 = _withdrawAllForUser(vault, strategyAddress, user2);
            vm.roll(block.number + 6);

            // ----------------- check results
            assertLe(_getDiffPercent4(deposited1, withdrawn1), 600, "deposited ~ withdrawn1"); // 6.0%
            assertLe(_getDiffPercent4(deposited2, withdrawn2), 600, "deposited ~ withdrawn2"); // 6.0%

            // ----------------- change amounts
            if (i % 2 == 0) {
                amount1 = amount1 * 31419/10000;
            } else {
                amount1 = amount1 / 3;
            }

            if (i % 2 == 0) {
                amount2 = amount2 * 31419/10000;
            } else {
                amount2 = amount2 / 2;
            }
        }
    }

    /// @notice Multiple deposit + withdraw all, two users
    function testSiLUpgradeMultipleDepositWithdrawHalfTwoUsers() public {
        address user1 = address(1);
        address user2 = address(2);

        vm.prank(multisig);
        address vault = VAULT2;
        address strategyAddress = address(IVault(vault).strategy());

        uint amount1 = 10_000e18;
        uint amount2 = 1_000e18;
        uint COUNT = 10;

        // ----------------- deploy new impl and upgrade
        _upgradeStrategy(strategyAddress);

        SiloLeverageStrategy strategy = SiloLeverageStrategy(payable(strategyAddress));
        vm.stopPrank();

        // ----------------- set up
//        _setFlashLoanVault(
//            strategy,
//            SHADOW_POOL_S_STS,
//            address(0),
//            uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2)
//        );

        _setFlashLoanVault(
            strategy,
            ALGEBRA_WS_USDC_POOL,
            ALGEBRA_USDC_STS_POOL,
            uint(ILeverageLendingStrategy.FlashLoanKind.AlgebraV4_3)
        );

        _adjustParams(strategy);

        // ----------------- main logic
        uint deposited1;
        uint deposited2;
        uint withdrawn1;
        uint withdrawn2;

        for (uint i = 0; i < COUNT; ++i) {
            // console.log("*****************************************************", i);
            // ----------------- deposit & withdraw
            deposited1 += _depositForUser(vault, user1, amount1);
            vm.roll(block.number + 6);

            deposited2 += _depositForUser(vault, user2, amount2);
            vm.roll(block.number + 6);

            // _withdrawForUser(vault, strategyAddress, user1, amount);
            withdrawn1 += _withdrawForUserPartly(vault, strategyAddress, user1, 30);
            vm.roll(block.number + 6);

            withdrawn2 += _withdrawForUserPartly(vault, strategyAddress, user2, 15);
            vm.roll(block.number + 6);

            // ----------------- change amounts
            if (i % 2 == 0) {
                amount1 = amount1 * 31419/10000;
            } else {
                amount1 = amount1 / 3;
            }

            if (i % 2 == 0) {
                amount2 = amount2 * 31419/10000;
            } else {
                amount2 = amount2 / 2;
            }
        }

        withdrawn1 += _withdrawAllForUser(vault, strategyAddress, user1);
        vm.roll(block.number + 6);

        withdrawn2 += _withdrawAllForUser(vault, strategyAddress, user2);

        // ----------------- check results
        assertLe(_getDiffPercent4(deposited1, withdrawn1), 100, "deposited ~ withdrawn1"); // 1%
        assertLe(_getDiffPercent4(deposited2, withdrawn2), 100, "deposited ~ withdrawn2"); // 1%
    }

    //endregion -------------------------- Deposit and withdraw

    //region -------------------------- Deposit withdraw routines
    function _depositForUser(address vault, address user, uint depositAmount) internal returns (uint) {
        address[] memory assets = IStrategy(IVault(vault).strategy()).assets();

        // --------------------------- provide amount to the user
        deal(assets[0], user, depositAmount + IERC20(assets[0]).balanceOf(user));

        // --------------------------- state before deposit
        State memory stateBefore = _getHealth(vault, "!!!Before deposit");

        // --------------------------- deposit
        vm.startPrank(user);
        IERC20(assets[0]).approve(vault, depositAmount);
        uint[] memory amounts = new uint[](1);
        amounts[0] = depositAmount;
        IVault(vault).depositAssets(assets, amounts, 0, user);
        vm.stopPrank();

        // --------------------------- state after deposit
        State memory stateAfter = _getHealth(vault, "!!!After deposit");

        // --------------------------- check results
        _checkInvariants(stateBefore, stateAfter, true);
        return depositAmount;
    }

    function _withdrawAllForUser(address vault, address strategy, address user) internal returns (uint) {
        return _withdrawAmount(vault, strategy, user, IERC20(vault).balanceOf(user));
    }

    function _withdrawForUser(address vault, address strategy, address user, uint amount) internal returns (uint) {
        uint amountToWithdraw = Math.min(amount, IERC20(vault).balanceOf(user));
        return _withdrawAmount(vault, strategy, user, amountToWithdraw);
    }

    function _withdrawForUserPartly(address vault, address strategy, address user, uint percent) internal returns (uint) {
        return _withdrawAmount(vault, strategy, user, IERC20(vault).balanceOf(user) * percent / 100);
    }

    function _withdrawAmount(address vault, address strategy, address user, uint amount) internal returns (uint) {
        // --------------------------- state before withdraw
        State memory stateBefore = _getHealth(vault, "!!!Before withdraw");

        // --------------------------- withdraw
        address[] memory assets = IStrategy(strategy).assets();
        uint balanceBefore = IERC20(assets[0]).balanceOf(user);

        uint amountToReceive = amount * IStrategy(strategy).total() / IERC20(vault).totalSupply();

        vm.prank(user);
        IVault(vault).withdrawAssets(assets, amount, new uint[](1));

        // --------------------------- state after withdraw
        State memory stateAfter = _getHealth(vault, "!!!After withdraw");

        // --------------------------- check results
        _checkInvariants(stateBefore, stateAfter, false);

        uint withdrawn = IERC20(assets[0]).balanceOf(user) - balanceBefore;

        if (amountToReceive != 0 || withdrawn != 0) {
            assertLe(_getPositiveDiffPercent4(amountToReceive, withdrawn), 350, "User received required amount1"); // -3.5%
            assertLe(_getDiffPercent4(amountToReceive, withdrawn), 350, "User received required amount2"); // +3.5%
        }
        return withdrawn;
    }

    function _checkInvariants(State memory stateBefore, State memory stateAfter, bool deposit) internal pure {
        // --------------------------- check invariants
        assertLe(stateAfter.ltv, stateAfter.maxLtv, "ltv < max ltv");
        assertLe(stateAfter.leverage, stateAfter.maxLeverage, "leverage < max leverage");

        // --------------------------- check changes
        if (deposit) {
            if (stateBefore.leverage < stateBefore.targetLeverage) {
                // assertLe(stateBefore.leverage, stateAfter.leverage, "leverage is increased");
                // todo we need following condition to be met exactly
                //assertLe(stateAfter.leverage, stateAfter.targetLeverage, "leverage doesn't exceed targetLeverage");
                assertLe(
                    _getPositiveDiffPercent4(stateAfter.leverage, stateAfter.targetLeverage),
                    2_00,
                    "leverage doesn't exceed targetLeverage too much 1"
                );
            } else {
                // todo we need following condition to be met exactly
                // assertLe(stateAfter.leverage, stateBefore.leverage, "leverage is decreased");
                assertLe(
                    _getPositiveDiffPercent4(stateAfter.leverage, stateBefore.targetLeverage),
                    2_00,
                    "leverage doesn't exceed targetLeverage too much 2"
                );
                assertLe(stateAfter.targetLeverage, stateAfter.leverage, "leverage doesn't become less targetLeverage");
            }
        } else {
            if (stateBefore.leverage < stateBefore.targetLeverage) {
                assertLe(stateAfter.leverage, stateAfter.targetLeverage, "leverage doesn't exceed targetLeverage");
            } else {
                assertLe(stateAfter.leverage, stateBefore.leverage, "leverage is decreased after withdraw");
            }
        }
    }
    //endregion -------------------------- Deposit withdraw routines

    //region -------------------------- Auxiliary functions
    function _getHealth(address vault, string memory stateName) internal view returns (State memory state) {
        SiloLeverageStrategy strategy = SiloLeverageStrategy(payable(address(IVault(vault).strategy())));
        // console.log(stateName);

        (state.ltv, state.maxLtv, state.leverage, state.collateralAmount, state.debtAmount, state.targetLeveragePercent) = strategy.health();
        state.total = strategy.total();
        (state.sharePrice,) = strategy.realSharePrice();
        state.maxLeverage = 100_00 * 1e18 / (1e18 - state.maxLtv);
        state.stateName = stateName;
        state.targetLeverage = state.maxLeverage * state.targetLeveragePercent / 100_00;

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

    function getSharePriceAndTvl(SiloLeverageStrategy strategy)
    internal
    view
    returns (uint sharePrice, uint tvl)
    {
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
        params[0] = 10000; // depositParam0: use default flash amount
        params[2] = 10000; // withdrawParam0: use default flash amount
        params[3] = 20000; // withdrawParam1: allow 200% of deposit after withdraw
        params[11] = 9500; // withdrawParam2: allow withdraw-through-increasing-ltv if leverage < 95% of target level
        vm.prank(multisig);
        strategy.setUniversalParams(params, addresses);
    }

    function _setFlashLoanVault(SiloLeverageStrategy strategy, address vaultC, address vaultB, uint kind) internal {
        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();
        params[10] = kind;
        addresses[0] = vaultC;
        addresses[1] = vaultB;

        vm.prank(multisig);
        strategy.setUniversalParams(params, addresses);
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
    //endregion -------------------------- Auxiliary functions

}
