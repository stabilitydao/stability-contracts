// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SonicSetup} from "../base/chains/SonicSetup.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {IFarmingStrategy} from "../../src/interfaces/IFarmingStrategy.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {IEVC, IEthereumVaultConnector} from "../../src/integrations/euler/IEthereumVaultConnector.sol";
import {IEulerVault} from "../../src/integrations/euler/IEulerVault.sol";
import {EMFLib} from "../../src/strategies/libs/EMFLib.sol";

contract EulerMerklFarmStrategyTestSonic is SonicSetup, UniversalTest {
    uint internal constant FORK_BLOCK = 45436518; // Sep-02-2025 03:36:10 AM +UTC

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        makePoolVolumePriceImpactTolerance = 9_000;
    }

    function testEMF() public universalTest {
        _addStrategy(62);
        _addStrategy(63);
    }

    //region -------------------------------- Universal test overrides

    /// @notice Add additional tests for maxWithdrawAssets, poolTvl, maxDepositAssets
    function _preDeposit() internal override {
        if (address(_getEulerVaultForCurrentStrategy()) == SonicConstantsLib.EULER_MERKL_USDC_MEV_CAPITAL) {
            uint shapshot = vm.snapshotState();
            _testPoolTvl();
            vm.revertToState(shapshot);

            shapshot = vm.snapshotState();
            _testMaxDeposit();
            vm.revertToState(shapshot);

            shapshot = vm.snapshotState();
            _testMaxWithdrawAssets();
            vm.revertToState(shapshot);

            shapshot = vm.snapshotState();
            _testEarningRewards();
            vm.revertToState(shapshot);
        }
    }

    function _addStrategy(uint farmId) internal {
        strategies.push(
            Strategy({
                id: StrategyIdLib.EULER_MERKL_FARM,
                pool: address(0),
                farmId: farmId,
                strategyInitAddresses: new address[](0),
                strategyInitNums: new uint[](0)
            })
        );
    }

    function _preHardWork() internal override {
        // emulate rewards receiving (workaround difficulties with merkl claiming)
        // currently rEUL are not supported here
        deal(SonicConstantsLib.TOKEN_WS, currentStrategy, 10e18);
    }
    //endregion -------------------------------- Universal test overrides

    //region -------------------------------- Additional tests

    function _testMaxDeposit() internal {
        IStrategy strategy = IStrategy(currentStrategy);

        // --------------------- Ensure that we cannot deposit more than maxDepositAssets
        uint[] memory tooHighAmounts = strategy.maxDepositAssets();
        tooHighAmounts[0] = tooHighAmounts[0] * 101 / 100;

        uint snapshot = vm.snapshotState();
        _tryToDepositToVault(strategy.vault(), tooHighAmounts, address(this), false);
        vm.revertToState(snapshot);

        // --------------------- Ensure that we can deposit maxDepositAssets
        snapshot = vm.snapshotState();
        uint[] memory amounts = strategy.maxDepositAssets();
        _tryToDepositToVault(strategy.vault(), amounts, address(this), true);
        vm.revertToState(snapshot);
    }

    function _testMaxWithdrawAssets() internal {
        IPlatform _platform = IPlatform(IControllable(currentStrategy).platform());
        IStrategy _strategy = IStrategy(currentStrategy);
        IStabilityVault _vault = IStabilityVault(_strategy.vault());
        //(uint vaultPrice,) = _vault.price();
        uint vaultPrice = 1e6; // there were no deposits, price is 0
        (uint assetPrice,) = IPriceReader(_platform.priceReader()).getPrice(_vault.assets()[0]);

        // --------------------- Deposit large amount
        uint maxWithdraw;
        {
            uint maxDeposit = _strategy.maxDepositAssets()[0];
            uint[] memory amountsToDeposit = new uint[](1);
            amountsToDeposit[0] = maxDeposit * 1 / 10;
            (uint deposited,) = _tryToDepositToVault(_strategy.vault(), amountsToDeposit, address(this), true);

            // --------------------- Ensure that we can withdraw all
            uint shapshot = vm.snapshotState();

            maxWithdraw = _vault.maxWithdraw(address(this));

            uint[] memory expectedAmounts = new uint[](1);
            expectedAmounts[0] = maxWithdraw * vaultPrice / assetPrice;

            uint[] memory withdrawn = _vault.withdrawAssets(_vault.assets(), maxWithdraw, expectedAmounts);

            assertApproxEqAbs(withdrawn[0], deposited, deposited / 100, "Should be able to withdraw all deposited");
            assertApproxEqAbs(
                withdrawn[0], expectedAmounts[0], expectedAmounts[0] / 100, "Should be equal to expected amount"
            );

            vm.revertToState(shapshot);
        }

        // --------------------- Other user borrows almost all cash from Euler
        {
            IEulerVault eulerVault = _getEulerVaultForCurrentStrategy();

            _borrowAlmostAllCash(_platform, eulerVault, 0.5e18); // borrow 50% of collateral in USDC
        }

        // --------------------- Ensure that maxWithdrawAssets returns less amount
        uint maxWithdrawAfter = _vault.maxWithdraw(address(this));
        assertLt(maxWithdrawAfter, maxWithdraw, "maxWithdrawAssets should decrease after borrow");

        // --------------------- Ensure that we cannot withdraw more than maxWithdrawAssets
        {
            uint[] memory expectedAmounts = new uint[](1);
            expectedAmounts[0] = maxWithdraw * vaultPrice / assetPrice;

            address[] memory _assets = _vault.assets();

            vm.expectRevert(IEulerVault.E_InsufficientCash.selector);
            _vault.withdrawAssets(_assets, maxWithdraw, expectedAmounts);
        }

        // --------------------- Ensure that we can withdraw maxWithdrawAssets
        _vault.withdrawAssets(_vault.assets(), maxWithdrawAfter, new uint[](1));
    }

    function _testPoolTvl() internal {
        IPlatform _platform = IPlatform(IControllable(currentStrategy).platform());
        IStrategy _strategy = IStrategy(currentStrategy);
        IStabilityVault _vault = IStabilityVault(_strategy.vault());

        IEulerVault eulerVault = _getEulerVaultForCurrentStrategy();

        // --------------------- State before deposit
        uint cashBefore = eulerVault.cash();
        uint tvlUsdBefore = _strategy.poolTvl();

        // --------------------- Deposit to the strategy
        uint[] memory amountsToDeposit = new uint[](1);
        amountsToDeposit[0] = _strategy.maxDepositAssets()[0] / 10;
        (uint deposited,) = _tryToDepositToVault(_strategy.vault(), amountsToDeposit, address(this), true);

        (uint priceAsset,) = IPriceReader(_platform.priceReader()).getPrice(_vault.assets()[0]);

        uint cashAfter = eulerVault.cash();
        uint tvlUsdAfter = _strategy.poolTvl();

        // --------------------- Check poolTvl values
        assertApproxEqAbs(cashAfter, cashBefore + deposited, 1, "Euler cash should increase on deposited amount");
        assertApproxEqAbs(
            tvlUsdAfter,
            tvlUsdBefore + deposited * priceAsset * 1e18 / 1e18 / 1e6,
            1,
            "TVL should increase on deposited amount"
        );
    }

    function _testEarningRewards() internal {
        IStrategy _strategy = IStrategy(currentStrategy);
        IStabilityVault _vault = IStabilityVault(_strategy.vault());

        // --------------------- Deposit to the strategy
        uint[] memory amountsToDeposit = new uint[](1);
        amountsToDeposit[0] = 100e6;

        (uint deposited,) = _tryToDepositToVault(address(_vault), amountsToDeposit, address(this), true);

        // --------------------- Hardwork
        vm.warp(block.timestamp + 3 days);

        // emulate rewards receiving
        // assume that strategy receives at least 2 times more than initial deposit
        deal(SonicConstantsLib.TOKEN_WS, currentStrategy, 1000e18);

        vm.prank(address(_vault));
        _strategy.doHardWork();

        // --------------------- Withdraw all and check results
        uint balance = _vault.balanceOf(address(this));
        uint[] memory withdrawn = _vault.withdrawAssets(_vault.assets(), balance, new uint[](1));

        assertGt(withdrawn[0], 2 * deposited, "Should earn rewards");
    }
    //endregion -------------------------------- Additional tests

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

    function _borrowAlmostAllCash(IPlatform platform, IEulerVault eulerVault, uint percent18) internal {
        IEulerVault collateralVault = IEulerVault(SonicConstantsLib.EULER_VAULT_WETH_MEV);
        IEthereumVaultConnector evc = IEthereumVaultConnector(payable(collateralVault.EVC()));

        uint collateralAmountETH;
        {
            (uint16 supplyCap,) = collateralVault.caps();
            uint amountSupplyCap = EMFLib._resolve(supplyCap);

            uint totalSupply = collateralVault.totalAssets(); // = convertToAssets(totalSupply())
            collateralAmountETH = (amountSupplyCap > totalSupply ? (amountSupplyCap - totalSupply) : 0) * 9 / 10;
        }

        deal(SonicConstantsLib.TOKEN_WETH, address(this), collateralAmountETH);
        IERC20(SonicConstantsLib.TOKEN_WETH).approve(address(collateralVault), collateralAmountETH);

        IPriceReader priceReader = IPriceReader(platform.priceReader());

        uint borrowAmount;
        {
            (uint priceUsdc,) = priceReader.getPrice(SonicConstantsLib.TOKEN_USDC);
            (uint priceEth,) = priceReader.getPrice(SonicConstantsLib.TOKEN_WETH);

            borrowAmount = collateralAmountETH * priceEth / priceUsdc * percent18 / 1e18; // borrow % of collateral in USDC

            borrowAmount = Math.min(borrowAmount, eulerVault.cash() * 9 / 10);
        }

        // console.log("Enabling borrow controller...");
        evc.enableController(address(this), address(eulerVault));

        // console.log("Enabling collateral...");
        evc.enableCollateral(address(this), address(collateralVault));

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](2);

        bytes memory depositData =
            abi.encodeWithSelector(IEulerVault.deposit.selector, collateralAmountETH, address(this));
        items[0] = IEVC.BatchItem({
            targetContract: address(collateralVault), onBehalfOfAccount: address(this), value: 0, data: depositData
        });

        bytes memory borrowData = abi.encodeWithSelector(IEulerVault.borrow.selector, borrowAmount, address(this));
        items[1] = IEVC.BatchItem({
            targetContract: address(eulerVault), onBehalfOfAccount: address(this), value: 0, data: borrowData
        });

        uint cashBefore = eulerVault.cash();
        evc.batch(items);
        assertGt(cashBefore, eulerVault.cash(), "Euler cash was not borrowed");
    }

    function _getEulerVaultForCurrentStrategy() internal view returns (IEulerVault) {
        IPlatform _platform = IPlatform(IControllable(currentStrategy).platform());
        uint farmId = IFarmingStrategy(currentStrategy).farmId();
        IFactory.Farm memory farm = IFactory(_platform.factory()).farm(farmId);
        return IEulerVault(farm.addresses[1]);
    }

    //endregion -------------------------------- Internal logic

    //region --------------------------------- Helpers
    function _dealAndApprove(address user, address metavault, address[] memory assets, uint[] memory amounts) internal {
        for (uint j; j < assets.length; ++j) {
            deal(assets[j], user, amounts[j]);
            vm.prank(user);
            IERC20(assets[j]).approve(metavault, amounts[j]);
        }
    }
    //endregion --------------------------------- Helpers
}
