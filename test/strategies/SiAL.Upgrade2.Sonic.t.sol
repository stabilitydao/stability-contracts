// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ISilo} from "../../src/integrations/silo/ISilo.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {console, Test} from "forge-std/Test.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
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

    uint internal constant FLASH_LOAN_KIND_BALANCER_V3 = 1;
    uint internal constant FLASH_LOAN_KIND_UNISWAP_V3 = 2;

    address public constant VAULT_aSonUSDC = 0x6BD40759E38ed47EF360A8618ac8Fe6d3b2EA959; // C-PT-aSonUSDC-14AUG2025-SAL;

    address public multisig;
    IFactory public factory;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        // vm.rollFork(22987373); // Apr-29-2025 02:42:43 AM +UTC
        // vm.rollFork(23744356); // May-02-2025 09:18:23 AM +UTC
        vm.rollFork(24504011); // May-05-2025 11:38:28 AM +UTC

        factory = IFactory(IPlatform(PLATFORM).factory());
        multisig = IPlatform(PLATFORM).multisig();
    }

    /// @notice #254: C-PT-aSonUSDC-14AUG2025-SAL. Rebalance, deposit 100_000, (LARGE) withdraw ALL
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
        address collateralAsset = IStrategy(strategy).assets()[0];
        _showHealth(strategy, "!!!Initial state");

        // ----------------- restore LTV to 80%
        console.log("!!!Rebalance to 80%");

        vm.startPrank(multisig);
        strategy.rebalanceDebt(80_00, 0);
        vm.stopPrank();

        uint ltvAfterRebalance = _showHealth(strategy, "!!!After rebalanceDebt");
        assertApproxEqAbs(ltvAfterRebalance, 80_00, 1001);

        // ----------------- deposit large amount
        console.log("!!!Deposit");
        _depositForUser(vault, address(strategy), user1, 100_000e6);
        uint ltvAfterDeposit = _showHealth(strategy, "!!!After deposit 1");
        assertApproxEqAbs(ltvAfterRebalance, ltvAfterDeposit, 500);

        // ----------------- withdraw all
        vm.roll(block.number + 6);
        console.log("!!!Withdraw");
        _withdrawAllForUser(vault, address(strategy), user1);
        _showHealth(strategy, "!!!After withdraw 1");

        console.log("balance user1", IERC20(collateralAsset).balanceOf(user1));
        assertApproxEqAbs(IERC20(collateralAsset).balanceOf(user1), 100_000e6, 4000e6);
    }

    /// @notice #247: decimals 6:18: C-PT-wstkscUSD-29MAY2025-SAL.
    /// Deposit user 2, Deposit user 1, withdraw part 1, withdraw all 1, withdraw all 2
    // Try to use flash loan of Uniswap V3
    function testSiALUpgrade2() public {
        console.log("testSiALUpgrade2");
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

        // ----------------- set up free balancer v3 flash loan

        // current flash loan vault is 0xBA12222222228d8Ba445958a75a0704d566BF2C8
        // we need to get Frax USD
        // !TODO _setFlashLoanVault(strategy, BEETS_VAULT_V3, FLASH_LOAN_KIND_BALANCER_V3);
        _setFlashLoanVault(strategy, SHADOW_POOL_FRXUSD_SCUSD, FLASH_LOAN_KIND_UNISWAP_V3);

        // ----------------- check current state
        _showHealth(strategy, "!!!Initial state");

        // ----------------- deposit large amount
        address collateralAsset = IStrategy(strategy).assets()[0];

        console.log("!!!Deposit user2");
        _depositForUser(vault, address(strategy), user2, 2e6);
        uint ltvAfterDeposit2 = _showHealth(strategy, "!!!After deposit 2");

        console.log("!!!Deposit user1");
        _depositForUser(vault, address(strategy), user1, 1000e6);
        uint ltvAfterDeposit1 = _showHealth(strategy, "!!!After deposit 1");
        assertApproxEqAbs(ltvAfterDeposit2, ltvAfterDeposit1, 100);

        // ----------------- user1: withdraw half
        console.log("!!!Withdraw user1");
        vm.roll(block.number + 6);
        console.log("Balance", IERC20(vault).balanceOf(user1));
        _withdrawForUser(vault, address(strategy), user1, IERC20(vault).balanceOf(user1) * 4 / 5);
        uint ltvAfterWithdraw1 = _showHealth(strategy, "!!!After withdraw 1 half");

        // ----------------- user1: withdraw all
        vm.roll(block.number + 6);
        _withdrawAllForUser(vault, address(strategy), user1);
        uint ltvAfterWithdraw1all = _showHealth(strategy, "!!!After withdraw 1 all");

        // ----------------- user2: withdraw all
        console.log("!!!Withdraw user2");
        vm.roll(block.number + 6);
        _withdrawAllForUser(vault, address(strategy), user2);
        /*uint ltvAfterWithdraw2 = */
        _showHealth(strategy, "!!!After withdraw 2 all");

        console.log("ltvAfterWithdraw1", ltvAfterWithdraw1);
        console.log("ltvAfterWithdraw1all", ltvAfterWithdraw1all);
        console.log("ltvAfterDeposit2", ltvAfterDeposit2);
        console.log("balance user1", IERC20(collateralAsset).balanceOf(user1));
        console.log("balance user2", IERC20(collateralAsset).balanceOf(user2));

        assertLe(_getDiffPercent(IERC20(collateralAsset).balanceOf(user1), 1000e6), 100);
        assertLe(_getDiffPercent(IERC20(collateralAsset).balanceOf(user2), 2e6), 100);

        console.log("done");
    }

    /// @notice #254: C-PT-aSonUSDC-14AUG2025-SAL. Deposit 10_000, withdraw half, withdraw all
    function testSiALUpgrade3() public {
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
            console.log("!!!START deposit user 1");
            console.log("PART", parts[i]);
            _depositForUser(vault, address(strategy), user1, 10_000e6);
            _showHealth(strategy, "!!!After deposit user1");

            // ----------------- user1: withdraw partly
            vm.roll(block.number + 6);
            console.log("!!!Withdraw1");
            _withdrawForUser(vault, address(strategy), user1, IERC20(vault).balanceOf(user1) * parts[i] / 100_00);
            _showHealth(strategy, "!!!After withdraw 1");

            if (parts[i] < 50_00) {
                vm.roll(block.number + 6);
                console.log("!!!Withdraw2");
                _withdrawForUser(vault, address(strategy), user1, IERC20(vault).balanceOf(user1) * parts[i] / 100_00);
                _showHealth(strategy, "!!!After withdraw 2");
            }

            // ----------------- user1: withdraw all
            vm.roll(block.number + 6);
            console.log("!!!Withdraw ALL");
            _withdrawAllForUser(vault, address(strategy), user1);

            uint ltvFinal = _showHealth(strategy, "!!!After withdraw all");

            console.log("balance user1", IERC20(IStrategy(strategy).assets()[0]).balanceOf(user1));
            console.log("User balance", IERC20(IStrategy(strategy).assets()[0]).balanceOf(user1));
            console.log("ltvFinal", ltvFinal);
            assertApproxEqAbs(IERC20(IStrategy(strategy).assets()[0]).balanceOf(user1), 10_000e6, 200e6);
            assertLe(ltvFinal, 92_00); // maxLTV = 0.92
        }

        (uint sharePrice1, uint tvl1) = getSharePriceAndTvl(strategy);
        if (sharePrice0 != 0) {
            console.log("sharePrice", sharePrice0, sharePrice1);
            console.log(_getDiffPercent(sharePrice0, sharePrice1));
            assertLe(_getDiffPercent(sharePrice0, sharePrice1), 5);
        }
        if (tvl0 != 0) {
            console.log("tvl", tvl0, tvl1);
            console.log(_getDiffPercent(tvl0, tvl1));
            assertLe(_getDiffPercent(tvl0, tvl1), 5);
        }
    }

    /// @notice Try to use flash loan of Beets V3
    function testSiALUpgrade4() public {
        console.log("testSiALUpgrade4");
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

        _setFlashLoanVault(strategy, BEETS_VAULT_V3, FLASH_LOAN_KIND_BALANCER_V3);

        // ----------------- check current state
        _showHealth(strategy, "!!!Initial state");

        // ----------------- deposit large amount
        address collateralAsset = IStrategy(strategy).assets()[0];

        console.log("!!!Deposit user2");
        _depositForUser(vault, address(strategy), user2, 2e6);
        _showHealth(strategy, "!!!After deposit 2");

        console.log("!!!Deposit user1");
        _depositForUser(vault, address(strategy), user1, 200_000e6);
        _showHealth(strategy, "!!!After deposit 1");

        // ----------------- user1: withdraw half
        console.log("!!!Withdraw user1");
        vm.roll(block.number + 6);
        console.log("Balance", IERC20(vault).balanceOf(user1));
        _withdrawForUser(vault, address(strategy), user1, IERC20(vault).balanceOf(user1) * 4 / 5);
        uint ltvAfterWithdraw1 = _showHealth(strategy, "!!!After withdraw 1 half");

        // ----------------- user1: withdraw all
        vm.roll(block.number + 6);
        _withdrawAllForUser(vault, address(strategy), user1);
        uint ltvAfterWithdraw1all = _showHealth(strategy, "!!!After withdraw 1 all");

        // ----------------- user2: withdraw all
        console.log("!!!Withdraw user2");
        vm.roll(block.number + 6);
        _withdrawAllForUser(vault, address(strategy), user2);
        /*uint ltvAfterWithdraw2 = */
        _showHealth(strategy, "!!!After withdraw 2 all");

        console.log("ltvAfterWithdraw1", ltvAfterWithdraw1);
        console.log("ltvAfterWithdraw1all", ltvAfterWithdraw1all);
        uint balance1 = IERC20(collateralAsset).balanceOf(user1);
        uint balance2 = IERC20(collateralAsset).balanceOf(user2);
        console.log("balance user1", balance1);
        console.log("balance user2", balance2);

        assertLe(
            (balance1 > 200_000e6
                ? balance1 - 200_000e6
                : 200_000e6 - balance1
            ) * 100_000 / 200_000e6,
            5_000 // (!) 5%
        );

        assertLe(
            (balance2 > 2e6
                ? balance2 - 2e6
                : 2e6 - balance2
            ) * 100_000 / 2e6,
            2_000 // (!) 2%
        );
    }

    /// @notice Try to make mixed deposits/withdraw
    /// Deposit 1,2; withdraw + deposit 1,2; withdraw all 1,2
    /// Various pools, various amounts
    function testSiALUpgrade5() public {
        console.log("testSiALUpgrade5");

        address[2] memory USERS = [address(1), address(2)];
        address[4] memory VAULTS = [
                0x4422117B942F4A87261c52348c36aeFb0DCDDb1a, // C-wanS-SAL
                0xd13369F16E11ae3881F22C1dD37957c241bD0662, // C-wOS-SAL
                0x03645841df5f71dc2c86bbdB15A97c66B34765b6, // Supply PT-wstkscUSD-29MAY2025 and borrow frxUSD
                0x6BD40759E38ed47EF360A8618ac8Fe6d3b2EA959 // C-PT-aSonUSDC-14AUG2025-SAL
            // 0x716ab48eC4054cf2330167C80a65B27cd57E09Cf, // C-PT-stS-29MAY2025-SAL
            // 0xadE710c52Cf4AB8bE1ffD292Ca266A6a4E49B2D2, // C-PT-wstkscETH-29MAY2025-SAL
                // 0x376ddBa57C649CEe95F93f827C61Af95ca519164, // Supply PT-wstkscUSD-29MAY2025 and borrow USDC.e
                // 0x908Db38302177901b10fFa74fA80AdAeB0351Ff1, // C-wstkscUSD-SAL
                // 0x425f26609e2309b9AB72cbF95092834e33B29A8a, // C-PT-wOS-29MAY2025-SAL
        // 0x46bc0F0073FF1a6281d401cDC6cd56Cec0495047, // C-wstkscETH-SAL
        // 0x59Ab350EE281a24a6D75d789E0264F2d4C3913b5, // C-PT-wstkscETH-29MAY2025-SAL
        ];
        uint16[4] memory BASE_AMOUNTS = [
                    10_000,
                    10_000,
                    50,
                    10_000
            // 10_000,
            // 10_000,
                    // 10_000,
                    //10_000,
                    //10_000,
                    //10_000,
                    //10_000,
            ];


        uint snapshotId = vm.snapshotState();
//        for (uint i = 0; i < 1; ++i) {
        for (uint i = 0; i < VAULTS.length; ++i) {
            uint[2] memory deposited = [uint(0), uint(0)];

            vm.revertToState(snapshotId);
            console.log("!!!Start vault", VAULTS[i]);

            // ----------------- deploy new impl and upgrade
            _upgradeStrategy(address(IVault(VAULTS[i]).strategy()));

            // ----------------- access to the strategy
            vm.prank(multisig);
            SiloAdvancedLeverageStrategy strategy = SiloAdvancedLeverageStrategy(payable(address(IVault(VAULTS[i]).strategy())));
            _adjustParams(strategy);
            vm.stopPrank();

            // ----------------- set up flashloan if necessary
            if (VAULTS[i] == 0x03645841df5f71dc2c86bbdB15A97c66B34765b6) {
                _setFlashLoanVault(strategy, SHADOW_POOL_FRXUSD_SCUSD, FLASH_LOAN_KIND_UNISWAP_V3);
            }

            // ----------------- check current state
            _showHealth(strategy, "!!!Initial state");

            // ----------------- deposit large amount
            uint amount = uint(BASE_AMOUNTS[i]) * 10 ** IERC20Metadata(strategy.assets()[0]).decimals();

            // ----------------- initial deposit
            console.log("!!!deposit2");
            deposited[1] += _depositForUser(VAULTS[i], address(strategy), USERS[1], i % 2 == 0 ? amount/(11 - i + 1) : amount * (11 - i + 1));
            _showHealth(strategy, "!!!After deposit2");

            console.log("!!!deposit1");
            deposited[0] += _depositForUser(VAULTS[i], address(strategy), USERS[0], i % 2 != 0 ? amount/(11 - i + 1) : amount * (11 - i + 1));
            _showHealth(strategy, "!!!After deposit1");

            // ----------------- withdraw
            console.log("!!!withdraw1");
            vm.roll(block.number + 6);
            _withdrawForUser(VAULTS[i], address(strategy), USERS[0], IERC20(VAULTS[i]).balanceOf(USERS[0]) * 15/100);
            _showHealth(strategy, "!!!After withdraw1");
            console.log("balance user 1", IERC20(strategy.assets()[0]).balanceOf(USERS[0]));
            console.log("balance user 2", IERC20(strategy.assets()[0]).balanceOf(USERS[1]));

            console.log("!!!withdraw2");
            vm.roll(block.number + 6);
            _withdrawForUser(VAULTS[i], address(strategy), USERS[1], IERC20(VAULTS[i]).balanceOf(USERS[1]) * 95/100);
            _showHealth(strategy, "!!!After withdraw2");
            console.log("balance user 1", IERC20(strategy.assets()[0]).balanceOf(USERS[0]));
            console.log("balance user 2", IERC20(strategy.assets()[0]).balanceOf(USERS[1]));

            // ----------------- deposit and withdraw
            console.log("!!!Deposit2");
            deposited[1] += _depositForUser(VAULTS[i], address(strategy), USERS[1], amount / (i + 1));
            _showHealth(strategy, "!!!After deposit2");
            console.log("balance user 1", IERC20(strategy.assets()[0]).balanceOf(USERS[0]));
            console.log("balance user 2", IERC20(strategy.assets()[0]).balanceOf(USERS[1]));

            console.log("!!!Withdraw1");
            vm.roll(block.number + 6);
            console.log("Balance", IERC20(VAULTS[i]).balanceOf(USERS[0]));
            _withdrawForUser(VAULTS[i], address(strategy), USERS[0], amount / 2);
            _showHealth(strategy, "!!!After Withdraw1");
            console.log("balance user 1", IERC20(strategy.assets()[0]).balanceOf(USERS[0]));
            console.log("balance user 2", IERC20(strategy.assets()[0]).balanceOf(USERS[1]));

            // ----------------- withdraw all
            console.log("!!!Withdraw all user1");
            vm.roll(block.number + 6);
            _withdrawAllForUser(VAULTS[i], address(strategy), USERS[0]);
            _showHealth(strategy, "!!!After withdraw 1 all");
            console.log("balance user 1", IERC20(strategy.assets()[0]).balanceOf(USERS[0]));
            console.log("balance user 2", IERC20(strategy.assets()[0]).balanceOf(USERS[1]));

            console.log("!!!Withdraw all user2");
            vm.roll(block.number + 6);
            _withdrawAllForUser(VAULTS[i], address(strategy), USERS[1]);
            console.log("balance user 1", IERC20(strategy.assets()[0]).balanceOf(USERS[0]));
            console.log("balance user 2", IERC20(strategy.assets()[0]).balanceOf(USERS[1]));

            _showHealth(strategy, "!!!After withdraw 2 all");

            // ----------------- check results

            console.log("!!!Done vault", VAULTS[i]);
            console.log("user1", deposited[0], IERC20(strategy.assets()[0]).balanceOf(USERS[0]));
            console.log("user2", deposited[1], IERC20(strategy.assets()[0]).balanceOf(USERS[1]));
            assertLe(_getDiffPercent(deposited[0], IERC20(strategy.assets()[0]).balanceOf(USERS[0])), 500); // 5%
            assertLe(_getDiffPercent(deposited[1], IERC20(strategy.assets()[0]).balanceOf(USERS[1])), 500); // 5%

        }
    }

    //region -------------------------- Auxiliary functions
    function _showHealth(SiloAdvancedLeverageStrategy strategy, string memory state) internal view returns (uint) {
        console.log(state);
        (uint ltv, uint maxLtv, uint leverage, uint collateralAmount, uint debtAmount, uint targetLeveragePercent) =
            strategy.health();
        console.log("ltv", ltv);
        console.log("maxLtv", maxLtv);
        console.log("leverage", leverage);
        console.log("collateralAmount", collateralAmount);
        console.log("debtAmount", debtAmount);
        console.log("targetLeveragePercent", targetLeveragePercent);
        console.log("Total amount in strategy", strategy.total());
        (uint sharePrice, ) = strategy.realSharePrice();
        console.log("realSharePrice", sharePrice);
        console.log("strategyTotal", strategy.total());

        return ltv;
    }

    function getSharePriceAndTvl(SiloAdvancedLeverageStrategy strategy) internal view returns (uint sharePrice, uint tvl) {
        (tvl,) = strategy.realTvl();
        (sharePrice,) = strategy.realSharePrice();
    }

    function _depositForUser(address vault, address strategy, address user, uint depositAmount) internal returns (uint){
        address[] memory assets = IStrategy(strategy).assets();
        console.log("deal", depositAmount);
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
        console.log("_withdrawForUser", amount, IERC20(vault).balanceOf(user), Math.min(amount, IERC20(vault).balanceOf(user)));
        address[] memory assets = IStrategy(strategy).assets();
        vm.prank(user);
        IVault(vault).withdrawAssets(
            assets,
            1e18, //Math.min(amount, IERC20(vault).balanceOf(user)),
            new uint[](1)
        );
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
        return x > y
            ? (x - y) * 100_00 / x
            : (y - x) * 100_00 / x;
    }
    //endregion -------------------------- Auxiliary functions
}
