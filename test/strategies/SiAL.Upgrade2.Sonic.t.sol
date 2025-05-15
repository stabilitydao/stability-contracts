// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ISilo} from "../../src/integrations/silo/ISilo.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {console, Test} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {SiloAdvancedLeverageStrategy} from "../../src/strategies/SiloAdvancedLeverageStrategy.sol";
import {CVault} from "../../src/core/vaults/CVault.sol";
import {VaultTypeLib} from "../../src/core/libs/VaultTypeLib.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

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

    address public constant VAULT_aSonUSDC = 0x6BD40759E38ed47EF360A8618ac8Fe6d3b2EA959; // C-PT-aSonUSDC-14AUG2025-SAL;

    address public constant ALGEBRA_POOL_FRXUSD_SFRXUSD = 0x7d709a567BA2fdBbB92E94E5fE74b9cbbc590835;

    address public multisig;
    IFactory public factory;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        // vm.rollFork(22987373); // Apr-29-2025 02:42:43 AM +UTC
        // vm.rollFork(23744356); // May-02-2025 09:18:23 AM +UTC
        // vm.rollFork(24504011); // May-05-2025 11:38:28 AM +UTC
        // vm.rollFork(26249931); // May-12-2025 01:01:38 PM +UTC
        vm.rollFork(26428190); // May-13-2025 06:22:27 AM +UTC

        factory = IFactory(IPlatform(PLATFORM).factory());
        multisig = IPlatform(PLATFORM).multisig();
    }

    /// @notice #254: C-PT-aSonUSDC-14AUG2025-SAL. Rebalance, deposit 100_000, (LARGE) withdraw ALL
    function testSiALUpgrade1() public {
        address user1 = address(1);
        uint amount = 40_000e6;
        // address user2 = address(2);

        // ----------------- deploy new impl and upgrade
        _upgradeStrategy(STRATEGY);

        // ----------------- access to the strategy
        vm.prank(multisig);
        address vault = IStrategy(STRATEGY).vault();
        SiloAdvancedLeverageStrategy strategy = SiloAdvancedLeverageStrategy(payable(STRATEGY));
        vm.stopPrank();

        // ----------------- check current state
        address collateralAsset = IStrategy(strategy).assets()[0];
        _showHealth(strategy, "!!!Initial state");

        // ----------------- restore LTV to 80%
        vm.startPrank(multisig);
        (uint sharePrice,) = strategy.realSharePrice();

        try strategy.rebalanceDebt(80_00, sharePrice * 101 / 100) {
            fail();
        } catch (bytes memory lowLevelData) {
            if (!(lowLevelData.length >= 4 && bytes4(lowLevelData) == IControllable.TooLowValue.selector)) {
                fail();
            }
        }

        strategy.rebalanceDebt(80_00, sharePrice * 90 / 100);
        vm.stopPrank();

        uint ltvAfterRebalance = _showHealth(strategy, "!!!After rebalanceDebt");
        assertApproxEqAbs(ltvAfterRebalance, 80_00, 1001);

        // ----------------- deposit large amount
        _depositForUser(vault, address(strategy), user1, amount);
        uint ltvAfterDeposit = _showHealth(strategy, "!!!After deposit 1");
        assertApproxEqAbs(ltvAfterRebalance, ltvAfterDeposit, 500);

        // ----------------- withdraw all
        vm.roll(block.number + 6);
        _withdrawAllForUser(vault, address(strategy), user1);
        _showHealth(strategy, "!!!After withdraw 1");

        assertLe(_getDiffPercent(IERC20(collateralAsset).balanceOf(user1), amount), 500);
    }

    /// @notice #247: decimals 6:18: C-PT-wstkscUSD-29MAY2025-SAL.
    /// Deposit user 2, Deposit user 1, withdraw part 1, withdraw all 1, withdraw all 2
    // Try to use flash loan of Uniswap V3
    function testSiALUpgrade2() public {
        address user1 = address(1);
        address user2 = address(2);
        address vault = IStrategy(STRATEGY2).vault();

        // ----------------- deploy new impl and upgrade
        _upgradeStrategy(STRATEGY2);
        // _upgradeVault(vault);

        // ----------------- access to the strategy
        vm.prank(multisig);
        SiloAdvancedLeverageStrategy strategy = SiloAdvancedLeverageStrategy(payable(STRATEGY2));
        _adjustParams(strategy);
        vm.stopPrank();

        // ----------------- set up free flash loan
        _setFlashLoanVault(
            strategy, ALGEBRA_POOL_FRXUSD_SFRXUSD, uint(ILeverageLendingStrategy.FlashLoanKind.AlgebraV4_3)
        );

        // ----------------- check current state
        _showHealth(strategy, "!!!Initial state");

        // ----------------- deposit large amount
        address collateralAsset = IStrategy(strategy).assets()[0];

        _depositForUser(vault, address(strategy), user2, 300e6);
        uint ltvAfterDeposit2 = _showHealth(strategy, "!!!After deposit 2");

        _depositForUser(vault, address(strategy), user1, 500e6);
        uint ltvAfterDeposit1 = _showHealth(strategy, "!!!After deposit 1");
        assertApproxEqAbs(ltvAfterDeposit2, ltvAfterDeposit1, 100);

        // ----------------- user1: withdraw all
        vm.roll(block.number + 6);
        _withdrawAllForUser(vault, address(strategy), user1);
        _showHealth(strategy, "!!!After withdraw 1 all");

        // ----------------- user2: withdraw all
        vm.roll(block.number + 6);
        _withdrawAllForUser(vault, address(strategy), user2);
        _showHealth(strategy, "!!!After withdraw 2 all");

        assertLe(_getDiffPercent(IERC20(collateralAsset).balanceOf(user1), 500e6), 100);
        assertLe(_getDiffPercent(IERC20(collateralAsset).balanceOf(user2), 300e6), 100);
    }

    /// @notice #254: C-PT-aSonUSDC-14AUG2025-SAL. Deposit 10_000, withdraw half, withdraw all
    function testSiALUpgrade3() public {
        address user1 = address(1);

        // ----------------- deploy new impl and upgrade
        _upgradeStrategy(STRATEGY);

        // ----------------- access to the strategy
        vm.prank(multisig);
        address vault = IStrategy(STRATEGY).vault();
        SiloAdvancedLeverageStrategy strategy = SiloAdvancedLeverageStrategy(payable(STRATEGY));
        vm.stopPrank();

        // ----------------- set up the strategy
        _setWithdrawParam1(strategy, 200_00);

        // ----------------- check current state
        _showHealth(strategy, "!!!Initial state");
        (uint sharePrice0, uint tvl0) = getSharePriceAndTvl(strategy);

        uint16[6] memory parts = [1_00, 10_00, 40_00, 60_00, 80_00, 99_99];
        //uint16[1] memory parts = [10_00];

        uint snapshotId = vm.snapshotState();
        for (uint i = 0; i < parts.length; ++i) {
            {
                bool reverted = vm.revertToState(snapshotId);
                assertTrue(reverted, "Failed to revert to snapshot");
            }

            // ----------------- user1: deposit large amount
            _depositForUser(vault, address(strategy), user1, 10_000e6);
            _showHealth(strategy, "!!!After deposit user1");

            // ----------------- user1: withdraw partly
            vm.roll(block.number + 6);
            _withdrawForUser(vault, address(strategy), user1, IERC20(vault).balanceOf(user1) * parts[i] / 100_00);
            _showHealth(strategy, "!!!After withdraw 1");

            if (parts[i] < 50_00) {
                vm.roll(block.number + 6);
                _withdrawForUser(vault, address(strategy), user1, IERC20(vault).balanceOf(user1) * parts[i] / 100_00);
                _showHealth(strategy, "!!!After withdraw 2");
            }

            // ----------------- user1: withdraw all
            vm.roll(block.number + 6);
            _withdrawAllForUser(vault, address(strategy), user1);

            uint ltvFinal = _showHealth(strategy, "!!!After withdraw all");

            assertApproxEqAbs(IERC20(IStrategy(strategy).assets()[0]).balanceOf(user1), 10_000e6, 200e6);
            assertLe(ltvFinal, 92_00); // maxLTV = 0.92
        }

        (uint sharePrice1, uint tvl1) = getSharePriceAndTvl(strategy);
        if (sharePrice0 != 0) {
            assertLe(_getDiffPercent(sharePrice0, sharePrice1), 5);
        }
        if (tvl0 != 0) {
            assertLe(_getDiffPercent(tvl0, tvl1), 5);
        }
    }

    /// @notice Try to use flash loan of Beets V3
    function testSiALUpgrade4() public {
        address user1 = address(1);
        address user2 = address(2);
        address vault = VAULT_aSonUSDC;

        // ----------------- deploy new impl and upgrade
        _upgradeStrategy(address(IVault(vault).strategy()));
        // _upgradeVault(vault);

        // ----------------- access to the strategy
        vm.prank(multisig);
        SiloAdvancedLeverageStrategy strategy = SiloAdvancedLeverageStrategy(payable(address(IVault(vault).strategy())));
        _adjustParams(strategy);
        vm.stopPrank();

        // ----------------- set up free balancer v3 flash loan

        _setFlashLoanVault(strategy, BEETS_VAULT_V3, uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1));

        // ----------------- check current state
        _showHealth(strategy, "!!!Initial state");

        // ----------------- deposit large amount
        address collateralAsset = IStrategy(strategy).assets()[0];

        _depositForUser(vault, address(strategy), user2, 2e6);
        _showHealth(strategy, "!!!After deposit 2");

        _depositForUser(vault, address(strategy), user1, 50_000e6);
        _showHealth(strategy, "!!!After deposit 1");

        // ----------------- user1: withdraw half
        vm.roll(block.number + 6);
        _withdrawForUser(vault, address(strategy), user1, IERC20(vault).balanceOf(user1) * 4 / 5);
        //uint ltvAfterWithdraw1 = _showHealth(strategy, "!!!After withdraw 1 half");

        // ----------------- user1: withdraw all
        vm.roll(block.number + 6);
        _withdrawAllForUser(vault, address(strategy), user1);

        // ----------------- user2: withdraw all
        vm.roll(block.number + 6);
        _withdrawAllForUser(vault, address(strategy), user2);
        _showHealth(strategy, "!!!After withdraw 2 all");

        uint balance1 = IERC20(collateralAsset).balanceOf(user1);
        uint balance2 = IERC20(collateralAsset).balanceOf(user2);

        //        console.log("balance1", balance1);
        //        console.log("balance2", balance2);
        assertLe(
            (balance1 > 50_000e6 ? balance1 - 50_000e6 : 50_000e6 - balance1) * 100_000 / 50_000e6,
            4_000 // (!) 4%
        );

        assertLe(
            (balance2 > 2e6 ? balance2 - 2e6 : 2e6 - balance2) * 100_000 / 2e6,
            4_000 // (!) 4%
        );
    }

    /// @notice Try to make mixed deposits/withdraw
    /// Deposit 1,2; withdraw + deposit 1,2; withdraw all 1,2
    /// Various pools, various amounts
    function testSiALUpgrade5() public {
        address[2] memory USERS = [address(1), address(2)];
        address[3] memory VAULTS = [
            0x4422117B942F4A87261c52348c36aeFb0DCDDb1a, // C-wanS-SAL
            // 0xd13369F16E11ae3881F22C1dD37957c241bD0662, // C-wOS-SAL   todo: IncorrectZeroAmount
            0x03645841df5f71dc2c86bbdB15A97c66B34765b6, // Supply PT-wstkscUSD-29MAY2025 and borrow frxUSD
            0x6BD40759E38ed47EF360A8618ac8Fe6d3b2EA959 // C-PT-aSonUSDC-14AUG2025-SAL
        ];
        uint16[3] memory BASE_AMOUNTS = [
            100,
            // 100,
            uint16(10),
            uint16(10000)
        ];

        uint snapshotId = vm.snapshotState();
        //        for (uint i = 0; i < 1; ++i) {
        for (uint i = 0; i < VAULTS.length; ++i) {
            uint[2] memory deposited = [uint(0), uint(0)];

            vm.revertToState(snapshotId);

            // ----------------- deploy new impl and upgrade
            _upgradeStrategy(address(IVault(VAULTS[i]).strategy()));

            // ----------------- access to the strategy
            vm.prank(multisig);
            SiloAdvancedLeverageStrategy strategy =
                SiloAdvancedLeverageStrategy(payable(address(IVault(VAULTS[i]).strategy())));
            _adjustParams(strategy);
            vm.stopPrank();

            // ----------------- set up flashloan if necessary
            if (VAULTS[i] == 0x03645841df5f71dc2c86bbdB15A97c66B34765b6) {
                _setFlashLoanVault(
                    strategy, SHADOW_POOL_FRXUSD_SCUSD, uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2)
                );
            }

            // ----------------- check current state
            _showHealth(strategy, "!!!Initial state");

            // ----------------- deposit large amount
            uint amount = uint(BASE_AMOUNTS[i]) * 10 ** IERC20Metadata(strategy.assets()[0]).decimals();

            // ----------------- initial deposit
            deposited[1] += _depositForUser(
                VAULTS[i], address(strategy), USERS[1], i % 2 == 0 ? amount / (11 - i + 1) : amount * (11 - i + 1)
            );
            _showHealth(strategy, "!!!After deposit2");

            deposited[0] += _depositForUser(
                VAULTS[i], address(strategy), USERS[0], i % 2 != 0 ? amount / (11 - i + 1) : amount * (11 - i + 1)
            );
            _showHealth(strategy, "!!!After deposit1");

            // ----------------- withdraw
            vm.roll(block.number + 6);
            _withdrawForUser(VAULTS[i], address(strategy), USERS[0], IERC20(VAULTS[i]).balanceOf(USERS[0]) * 15 / 100);
            _showHealth(strategy, "!!!After withdraw1");

            vm.roll(block.number + 6);
            _withdrawForUser(VAULTS[i], address(strategy), USERS[1], IERC20(VAULTS[i]).balanceOf(USERS[1]) * 95 / 100);
            _showHealth(strategy, "!!!After withdraw2");

            // ----------------- deposit and withdraw
            deposited[1] += _depositForUser(VAULTS[i], address(strategy), USERS[1], amount / (i + 1));
            _showHealth(strategy, "!!!After deposit2");

            vm.roll(block.number + 6);
            _withdrawForUser(VAULTS[i], address(strategy), USERS[0], amount / 2);
            _showHealth(strategy, "!!!After Withdraw1");

            // ----------------- withdraw all
            vm.roll(block.number + 6);
            _withdrawAllForUser(VAULTS[i], address(strategy), USERS[0]);
            _showHealth(strategy, "!!!After withdraw 1 all");

            vm.roll(block.number + 6);
            _withdrawAllForUser(VAULTS[i], address(strategy), USERS[1]);

            _showHealth(strategy, "!!!After withdraw 2 all");

            // ----------------- check results

            assertLe(_getDiffPercent(deposited[0], IERC20(strategy.assets()[0]).balanceOf(USERS[0])), 500); // 5%
            assertLe(_getDiffPercent(deposited[1], IERC20(strategy.assets()[0]).balanceOf(USERS[1])), 500); // 5%
        }
    }

    /// @notice #276: flash loan Algebra v4
    function testSiALUpgrade6() public {
        address user1 = address(1);
        address user2 = address(2);
        address vault = IStrategy(STRATEGY2).vault();

        // ----------------- deploy new impl and upgrade
        _upgradeStrategy(STRATEGY2);
        // _upgradeVault(vault);

        // ----------------- access to the strategy
        vm.prank(multisig);
        SiloAdvancedLeverageStrategy strategy = SiloAdvancedLeverageStrategy(payable(STRATEGY2));
        _adjustParams(strategy);
        vm.stopPrank();

        // ----------------- set up flash loan
        _setFlashLoanVault(
            strategy, ALGEBRA_POOL_FRXUSD_SFRXUSD, uint(ILeverageLendingStrategy.FlashLoanKind.AlgebraV4_3)
        );

        // ----------------- check current state
        _showHealth(strategy, "!!!Initial state");

        // ----------------- deposit large amount
        address collateralAsset = IStrategy(strategy).assets()[0];

        _depositForUser(vault, address(strategy), user2, 2e6);

        _depositForUser(vault, address(strategy), user1, 1000e6);

        // ----------------- user1: withdraw half
        vm.roll(block.number + 6);
        _withdrawForUser(vault, address(strategy), user1, IERC20(vault).balanceOf(user1) * 4 / 5);

        // ----------------- user1: withdraw all
        vm.roll(block.number + 6);
        _withdrawAllForUser(vault, address(strategy), user1);

        // ----------------- user2: withdraw all
        vm.roll(block.number + 6);
        _withdrawAllForUser(vault, address(strategy), user2);

        assertLe(_getDiffPercent(IERC20(collateralAsset).balanceOf(user1), 1000e6), 100);
        assertLe(_getDiffPercent(IERC20(collateralAsset).balanceOf(user2), 2e6), 100);
    }

    //region -------------------------- Auxiliary functions
    function _showHealth(SiloAdvancedLeverageStrategy strategy, string memory state) internal view returns (uint) {
        state;
        // console.log(state);
        //(uint ltv, uint maxLtv, uint leverage, uint collateralAmount, uint debtAmount, uint targetLeveragePercent) =
        (uint ltv,,,,,) = strategy.health();
        /*console.log("ltv", ltv);
        console.log("maxLtv", maxLtv);
        console.log("leverage", leverage);
        console.log("collateralAmount", collateralAmount);
        console.log("debtAmount", debtAmount);
        console.log("targetLeveragePercent", targetLeveragePercent);
        console.log("Total amount in strategy", strategy.total());
        (uint sharePrice,) = strategy.realSharePrice();
        console.log("realSharePrice", sharePrice);
        console.log("strategyTotal", strategy.total());*/

        return ltv;
    }

    function getSharePriceAndTvl(SiloAdvancedLeverageStrategy strategy)
        internal
        view
        returns (uint sharePrice, uint tvl)
    {
        (tvl,) = strategy.realTvl();
        (sharePrice,) = strategy.realSharePrice();
    }

    function _depositForUser(
        address vault,
        address strategy,
        address user,
        uint depositAmount
    ) internal returns (uint) {
        address[] memory assets = IStrategy(strategy).assets();
        deal(assets[0], user, depositAmount + IERC20(assets[0]).balanceOf(user));
        vm.startPrank(user);
        IERC20(assets[0]).approve(vault, depositAmount);
        uint[] memory amounts = new uint[](1);
        amounts[0] = depositAmount;
        IVault(vault).depositAssets(assets, amounts, 0, user);
        vm.stopPrank();

        return depositAmount;
    }

    function _withdrawAllForUser(address vault, address strategy, address user) internal {
        address[] memory assets = IStrategy(strategy).assets();
        uint bal = IERC20(vault).balanceOf(user);
        vm.prank(user);
        IVault(vault).withdrawAssets(assets, bal, new uint[](1));
    }

    function _withdrawForUser(address vault, address strategy, address user, uint amount) internal {
        uint amountToPay = Math.min(amount, IERC20(vault).balanceOf(user));
        address[] memory assets = IStrategy(strategy).assets();
        vm.prank(user);
        IVault(vault).withdrawAssets(assets, amountToPay, new uint[](1));
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
        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();
        params[0] = 10000;
        vm.prank(multisig);
        strategy.setUniversalParams(params, addresses);
    }

    function _setFlashLoanVault(SiloAdvancedLeverageStrategy strategy, address vault, uint kind) internal {
        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();
        params[10] = kind;
        addresses[0] = vault;

        vm.prank(multisig);
        strategy.setUniversalParams(params, addresses);
    }

    /// @notice withdrawParams1 increases withdraw amount (rest is deposited back after withdraw)
    function _setWithdrawParam1(SiloAdvancedLeverageStrategy strategy, uint withdrawParams1) internal {
        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();
        params[3] = withdrawParams1;
        vm.prank(multisig);
        strategy.setUniversalParams(params, addresses);
    }

    function _getDiffPercent(uint x, uint y) internal pure returns (uint) {
        return x > y ? (x - y) * 100_00 / x : (y - x) * 100_00 / x;
    }
    //endregion -------------------------- Auxiliary functions
}
