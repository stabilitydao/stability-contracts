// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../../src/core/Platform.sol";
import "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {SiloAdvancedLeverageStrategy} from "../../src/strategies/SiloAdvancedLeverageStrategy.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {console, Test} from "forge-std/Test.sol";
import {PendleAdapter} from "../../src/adapters/PendleAdapter.sol";
import {IPPrincipalToken} from "../../src/integrations/pendle/IPPrincipalToken.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";

contract SiALUpgradeExpiredPtTest is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    address public constant STRATEGY_PT = 0x2D34203886Da9ad7d1fe48FF7EF65a70f3788573;
    address public constant USER_PT = 0xFCd9df3BcdC746B23AB3FcF063F92C2Ca2D185B3;

    address public constant STRATEGY_W = 0x78080B52E639D9410F8c8f75E168072cd2617e6C;
    address public constant USER_W = 0x4ECe177350d5d474146242c3A0811c67762146F9;

    address public constant PENDLE_PT = 0x77d8F09053c28FaF1E00Df6511b23125d438616f;

    address[5] HOLDERS_VAULT_PT;

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
    }

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        // vm.rollFork(39805461); // Jul-23-2025 05:42:36 AM +UTC

        vm.rollFork(39816642); // Jul-23-2025 07:28:08 AM +UTC  expired
        // vm.rollFork(38716642); // Jul-16-2025 06:32:35 AM +UTC   not expired

        // we need to skip 1 day to update the swapper
        // but we cannot simply skip 1 day, because the silo oracle will start to revert with InvalidPrice
        vm.warp(block.timestamp - 86400);

        // different tests use different blocks
        HOLDERS_VAULT_PT = [
            0xFCd9df3BcdC746B23AB3FcF063F92C2Ca2D185B3, // largest
            0x959767f961E91dFbBf865490D1c99Cf4e421B9E9,
            0xA35c3fB06b17Af73b1b385144d47cf7f4624ae6e,
            0x23b8Cc22C4c82545F4b451B11E2F17747A730810,
            0x6F5791B0D0CF656fF13b476aF62afb93138AeAd9
        ];
    }

    function testExpiredPtLargestUser() public {
        // ------------------------- Prepare to withdraw
        IVault vault = IVault(IStrategy(STRATEGY_PT).vault());
        uint shares = vault.balanceOf(USER_PT);
        //console.log("balance", shares);

        address[] memory assets = vault.assets();
        uint balanceBefore = IERC20(assets[0]).balanceOf(USER_PT);

        // ------------------------- Ensure that we cannot withdraw before upgrade
        vm.expectRevert();
        vm.prank(USER_PT);
        vault.withdrawAssets(assets, shares, new uint[](1));
        // custom error 0xb2094b59

        // State memory stateBefore = _getHealth(address(vault));

        // ------------------------- Upgrade strategy and pendle adapter, set up the strategy
        _upgradeStrategy(STRATEGY_PT);
        _upgradePlatform();
        _adjustParams(ILeverageLendingStrategy(STRATEGY_PT));

        // ------------------------- Ensure that withdraw is possible without revert
        vm.prank(USER_PT);
        uint[] memory withdrawn = vault.withdrawAssets(assets, shares, new uint[](1));
        uint balanceAfter = IERC20(assets[0]).balanceOf(USER_PT);
        // State memory stateAfter = _getHealth(address(vault));

        assertGt(balanceAfter - balanceBefore, 0, "withdrawn balance should be greater than 0");
        assertEq(balanceAfter - balanceBefore, withdrawn[0], "withdrawn balance should match the returned value");
        // console.log("withdrawn balance", withdrawn[0]);
    }

    function testExpiredPtAllHolders() public {
        // ------------------------- Upgrade strategy and pendle adapter, set up the strategy
        _upgradeStrategy(STRATEGY_PT);
        _upgradePlatform();
        _adjustParams(ILeverageLendingStrategy(STRATEGY_PT));

        // ------------------------- Prepare to withdraw
        IVault vault = IVault(IStrategy(STRATEGY_PT).vault());
        // _getHealth(address(vault));

        address[] memory assets = vault.assets();
        uint total = IStrategy(STRATEGY_PT).total();
        uint totalWithdrawn;

        for (uint i; i < HOLDERS_VAULT_PT.length; ++i) {
            // console.log("i", i);
            uint shares = vault.balanceOf(HOLDERS_VAULT_PT[i]);
            uint balanceBefore = IERC20(assets[0]).balanceOf(HOLDERS_VAULT_PT[i]);
            //            (uint tvl, ) = vault.tvl();
            //            (uint price,) = vault.price();
            //            console.log("withdraw.shares, holder", shares, HOLDERS_VAULT_PT[i]);
            //            console.log("totalSupply, tvl, price", vault.totalSupply() / 1e18, tvl / 1e18, price);
            // ------------------------- Ensure that withdraw is possible without revert
            vm.prank(HOLDERS_VAULT_PT[i]);
            uint[] memory withdrawn = vault.withdrawAssets(assets, shares, new uint[](1));
            uint balanceAfter = IERC20(assets[0]).balanceOf(HOLDERS_VAULT_PT[i]);

            assertGt(balanceAfter - balanceBefore, 0, "M: withdrawn balance should be greater than 0");
            assertEq(balanceAfter - balanceBefore, withdrawn[0], "M: withdrawn balance should match the returned value");
            //console.log("withdrawn balance", withdrawn[0], assets[0]);
            _getHealth(address(vault));
            totalWithdrawn += withdrawn[0];
        }

        assertApproxEqAbs(total, totalWithdrawn, total / 100, "M: total should match the total withdrawn amount");
    }

    function testNotExpiredPtAllHolders() internal {
        // ------------------------- Upgrade strategy and pendle adapter, set up the strategy
        _upgradeStrategy(STRATEGY_PT);
        _upgradePlatform();
        //        _adjustParams(ILeverageLendingStrategy(STRATEGY_PT));

        // ------------------------- Prepare to withdraw
        IVault vault = IVault(IStrategy(STRATEGY_PT).vault());

        address[] memory assets = vault.assets();

        for (uint i; i < HOLDERS_VAULT_PT.length; ++i) {
            console.log("i", i);
            uint shares = vault.balanceOf(HOLDERS_VAULT_PT[i]);
            uint balanceBefore = IERC20(assets[0]).balanceOf(HOLDERS_VAULT_PT[i]);
            (uint tvl,) = vault.tvl();
            (uint price,) = vault.price();
            console.log("withdraw.shares, holder", shares / 1e18, HOLDERS_VAULT_PT[i]);
            console.log("totalSupply, tvl, price", vault.totalSupply() / 1e18, tvl / 1e18, price);

            // ------------------------- Ensure that withdraw is possible without revert
            vm.prank(HOLDERS_VAULT_PT[i]);
            uint[] memory withdrawn = vault.withdrawAssets(assets, shares, new uint[](1));
            uint balanceAfter = IERC20(assets[0]).balanceOf(HOLDERS_VAULT_PT[i]);

            assertGt(balanceAfter - balanceBefore, 0, "M: withdrawn balance should be greater than 0");
            assertEq(balanceAfter - balanceBefore, withdrawn[0], "M: withdrawn balance should match the returned value");
            console.log("withdrawn balance", withdrawn[0], assets[0]);
        }
    }

    function testWstkscusd() internal {
        // 0x6Fb30F3FCB864D49cdff15061ed5c6ADFEE40B40
        _upgradeStrategy(STRATEGY_W);
        _upgradePlatform();
        _setFlashLoanVault(ILeverageLendingStrategy(STRATEGY_W));

        IVault vault = IVault(IStrategy(STRATEGY_W).vault());
        uint shares = vault.balanceOf(USER_W);
        console.log("balance", shares);

        address[] memory assets = vault.assets();
        uint balanceBefore = IERC20(assets[0]).balanceOf(USER_W);

        vm.prank(USER_W);
        uint[] memory withdrawn = vault.withdrawAssets(assets, shares, new uint[](1));
        uint balanceAfter = IERC20(assets[0]).balanceOf(USER_W);

        console.log("withdrawn balance", balanceAfter - balanceBefore, withdrawn[0]);
    }

    //region ---------------------------------------- Helpers

    function _setFlashLoanVault(ILeverageLendingStrategy strategy) internal {
        address multisig = IPlatform(PLATFORM).multisig();

        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();
        for (uint i; i < params.length; i++) {
            console.log("param", i, params[i]);
        }
        for (uint i; i < addresses.length; i++) {
            console.log("address", i, addresses[i]);
        }

        //        console.log("kind", params[10]);
        //        console.log("a1", addresses[0]);
        params[10] = uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2);
        addresses[0] = 0x6Fb30F3FCB864D49cdff15061ed5c6ADFEE40B40;
        //        console.log("kind", params[10]);
        //        console.log("a1", addresses[0]);

        vm.prank(multisig);
        strategy.setUniversalParams(params, addresses);
    }

    function _upgradeStrategy(address strategy_) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());
        address multisig = IPlatform(PLATFORM).multisig();

        // deploy new impl and upgrade
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

        factory.upgradeStrategyProxy(strategy_);
    }

    function _upgradePlatform() internal {
        address multisig = IPlatform(PLATFORM).multisig();

        address[] memory proxies = new address[](1);
        proxies[0] = IPlatform(PLATFORM).ammAdapter(keccak256(bytes(AmmAdapterIdLib.PENDLE))).proxy;

        address[] memory implementations = new address[](1);
        implementations[0] = address(new PendleAdapter());

        vm.startPrank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.05.0-alpha", proxies, implementations);
        skip(1 days);
        IPlatform(PLATFORM).upgrade();
        vm.stopPrank();
    }

    function _adjustParams(ILeverageLendingStrategy strategy) internal {
        address multisig = IPlatform(PLATFORM).multisig();

        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();
        //        for (uint i; i < params.length; i++) {
        //            console.log("param", i, params[i]);
        //        }
        //        for (uint i; i < addresses.length; i++) {
        //            console.log("address", i, addresses[i]);
        //        }

        // params[0] = 10000; // depositParam0: use default flash amount
        params[1] = 1; // collateral asset is expired Pendle PT
        params[3] = 0; // withdrawParam1: don't allow deposit after withdraw
        params[11] = 0; // withdrawParam2: don't allow withdraw-through-increasing-ltv

        vm.prank(multisig);
        strategy.setUniversalParams(params, addresses);
    }

    function _getHealth(address vault) internal view returns (State memory state) {
        SiloAdvancedLeverageStrategy strategy = SiloAdvancedLeverageStrategy(payable(address(IVault(vault).strategy())));
        // console.log(stateName);

        (state.ltv, state.maxLtv, state.leverage, state.collateralAmount, state.debtAmount, state.targetLeveragePercent)
        = strategy.health();
        state.total = strategy.total();
        (state.sharePrice,) = strategy.realSharePrice();
        state.maxLeverage = 100_00 * 1e18 / (1e18 - state.maxLtv);
        state.targetLeverage = state.maxLeverage * state.targetLeveragePercent / 100_00;

        //                console.log("ltv", state.ltv);
        //                console.log("maxLtv", state.maxLtv);
        //                console.log("leverage", state.leverage);
        //                console.log("collateralAmount", state.collateralAmount);
        //                console.log("debtAmount", state.debtAmount);
        //                console.log("targetLeveragePercent", state.targetLeveragePercent);
        //                console.log("maxLeverage", state.maxLeverage);
        //                console.log("targetLeverage", state.targetLeverage);
        return state;
    }
    //endregion ---------------------------------------- Helpers
}
