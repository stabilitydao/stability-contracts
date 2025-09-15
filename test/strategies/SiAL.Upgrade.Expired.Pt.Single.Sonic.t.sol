// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Platform} from "../../src/core/Platform.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {SiloAdvancedLeverageStrategy} from "../../src/strategies/SiloAdvancedLeverageStrategy.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {console, Test} from "forge-std/Test.sol";
import {PendleAdapter} from "../../src/adapters/PendleAdapter.sol";
import {IPPrincipalToken} from "../../src/integrations/pendle/IPPrincipalToken.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {Swapper} from "../../src/core/Swapper.sol";

/// @dev Try to withdraw from expired Pendle strategies
/// @notice Set block for each test individually,
/// so we can add new expired strategies to this test at any time without changing previous tests
contract SiALUpgradeExpiredPtSingleTest is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    address public constant HOLDER_VAULT_LEV_SiAL_aSonUSDC_scUSD_14AUG2025 = 0xB48894f4318a310A3bC6E96bFa77307e8aa6196E;

    function testVaultSiAL_aSonUSDC_scUSD_14AUG2025() public {
        _withdrawFromExpiredPtVault(
            43926167, // Aug-21-2025 07:32:46 AM +UTC
            SonicConstantsLib.VAULT_LEV_SIAL_ASONUSDC_SCUSD_14AUG2025,
            HOLDER_VAULT_LEV_SiAL_aSonUSDC_scUSD_14AUG2025
        );
    }

    //region ---------------------------------------- Internal logic
    function _withdrawFromExpiredPtVault(uint block_, address vault_, address holder_) internal {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), block_));

        // ------------------------- Prepare to withdraw
        IVault vault = IVault(vault_);
        address strategy = address(vault.strategy());
        uint shares = vault.balanceOf(holder_);
        assertGt(shares, 0, "Shares should be greater than 0");

        address[] memory assets = vault.assets();
        uint balanceBefore = IERC20(assets[0]).balanceOf(holder_);

        uint expectedWithdraw = _getExpectedWithdraw(vault, holder_);

        // ------------------------- Ensure that we cannot withdraw before upgrade
        vm.expectRevert();
        vm.prank(holder_);
        vault.withdrawAssets(assets, shares, new uint[](1));

        // ------------------------- Set up expired market
        // _upgradeStrategy(strategy);
        // _upgradePlatform();
        _adjustParamsSetExpiredMarket(ILeverageLendingStrategy(strategy));

        // ------------------------- Ensure that withdraw is possible without revert
        vm.prank(holder_);
        uint[] memory withdrawn = vault.withdrawAssets(assets, shares, new uint[](1));
        uint balanceAfter = IERC20(assets[0]).balanceOf(holder_);

        assertApproxEqAbs(
            withdrawn[0], expectedWithdraw, 2 * expectedWithdraw / 100, "Withdrawn amount should be close to expected"
        );

        assertGt(balanceAfter - balanceBefore, 0, "Withdrawn balance should be greater than 0");
        assertEq(balanceAfter - balanceBefore, withdrawn[0], "Withdrawn balance should match the returned value");
    } //endregion ---------------------------------------- Internal logic

    //region ---------------------------------------- Helpers
    function _getExpectedWithdraw(IVault vault, address holder) internal view returns (uint expectedWithdraw) {
        uint shares = vault.balanceOf(holder);
        (uint realSharePrice,) = ILeverageLendingStrategy(address(vault.strategy())).realSharePrice();
        (uint assetPrice,) = IPriceReader(IPlatform(PLATFORM).priceReader()).getPrice(vault.assets()[0]);
        expectedWithdraw =
            shares * realSharePrice * 10 ** IERC20Metadata(vault.assets()[0]).decimals() / assetPrice / 1e18;
        //        console.log("withdraw.shares, holder", shares, holder);
        //        console.log("value, realSharePrice", value, realSharePrice);
        //        console.log("price, assetPrice, expectedWithdraw", price, assetPrice, expectedWithdraw);
        //            console.log("totalSupply, tvl, price", vault.totalSupply() / 1e18, tvl / 1e18, price);
    }

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
        // proxies[1] = IPlatform(PLATFORM).swapper();

        address[] memory implementations = new address[](1);
        implementations[0] = address(new PendleAdapter());
        // implementations[1] = address(new Swapper());

        vm.startPrank(multisig);
        IPlatform(PLATFORM).announcePlatformUpgrade("2025.05.0-alpha", proxies, implementations);
        skip(1 days);
        IPlatform(PLATFORM).upgrade();
        vm.stopPrank();
    }

    function _adjustParamsSetExpiredMarket(ILeverageLendingStrategy strategy) internal {
        address multisig = IPlatform(PLATFORM).multisig();

        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();

        params[1] = 1; // collateral asset is expired Pendle PT
        params[3] = 0; // withdrawParam1: don't allow deposit after withdraw
        params[11] = 0; // withdrawParam2: don't allow withdraw-through-increasing-ltv

        vm.prank(multisig);
        strategy.setUniversalParams(params, addresses);
    }
    //endregion ---------------------------------------- Helpers
}
