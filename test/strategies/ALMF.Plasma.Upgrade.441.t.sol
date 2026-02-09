// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/console.sol";
import {Test, Vm} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AaveLeverageMerklFarmStrategy} from "../../src/strategies/AaveLeverageMerklFarmStrategy.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {ILeverageLendingStrategy} from "../../src/interfaces/ILeverageLendingStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IFarmingStrategy} from "../../src/interfaces/IFarmingStrategy.sol";
import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {ALMFLib} from "../../src/strategies/libs/ALMFLib.sol";

/// @notice #441: Use depositParam1 and withdrawParam1 to set deposit/withdraw fee
contract ALMFUpgrade441PlasmaTest is Test {
    uint internal constant FORK_BLOCK = 13688033; // Feb-09-2026 06:49:49 AM +UTC

    /// @notice Stability weETH Aave Leverage Merkl Farm USDT0
    address internal constant VAULT = PlasmaConstantsLib.STABILITY_VAULT_ALMF_WEETH_USDT0;

    address internal multisig;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("PLASMA_RPC_URL"), FORK_BLOCK));

        _upgradeStrategy(address(IVault(VAULT).strategy()));
    }

    function testUpgradeStrategy() public {
        uint[4] memory depositParam1 = [uint(0), 10, 0, 10]; // 0.1% for deposit
        uint[4] memory withdrawParam1 = [uint(0), 0, 20, 20]; // 0.2 % for withdraw
        uint[4] memory withdrawn;
        uint[4] memory receivedByRevenueRouter;

        // --------------------------------- zero fee

        for (uint i; i < 4; ++i) {
            uint snapshot = vm.snapshotState();
            {
                ILeverageLendingStrategy strategy = ILeverageLendingStrategy(address(IVault(VAULT).strategy()));
                (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();
                params[1] = depositParam1[i];
                params[3] = withdrawParam1[i];
                vm.prank(PlasmaConstantsLib.MULTISIG);
                strategy.setUniversalParams(params, addresses);
            }

            uint before = IERC20(PlasmaConstantsLib.TOKEN_WEETH)
                .balanceOf(IPlatform(PlasmaConstantsLib.PLATFORM).revenueRouter());

            // deposit 1 weeth
            _depositToVault(VAULT, 1e18, address(this));

            vm.roll(block.number + 6);

            // withdraw all
            withdrawn[i] = _withdrawFromVault(VAULT, IVault(VAULT).balanceOf(address(this)), address(this));

            receivedByRevenueRouter[i] = IERC20(PlasmaConstantsLib.TOKEN_WEETH)
                .balanceOf(IPlatform(PlasmaConstantsLib.PLATFORM).revenueRouter()) - before;
            vm.revertToState(snapshot);
        }

        assertApproxEqAbs(withdrawn[0], withdrawn[1], 0.001e18, "~0.1% for deposit");
        assertApproxEqAbs(withdrawn[0], withdrawn[2], 0.002e18, "~0.2% for withdraw");
        assertApproxEqAbs(withdrawn[0], withdrawn[3], 0.003e18, "~0.3% for deposit and withdraw");

        assertEq(receivedByRevenueRouter[0], 0, "no fees for deposit and withdraw");
        assertEq(receivedByRevenueRouter[1], 0.001e18, "0.1% for deposit");
        assertApproxEqAbs(receivedByRevenueRouter[2], 0.002e18, 1e14, "0.2% for withdraw");
        assertApproxEqAbs(receivedByRevenueRouter[3], 0.003e18, 1e14, "0.3% for deposit and withdraw");
    }

    function _depositToVault(
        address vault,
        uint amount,
        address user
    ) internal returns (uint deposited, uint depositedValue) {
        address[] memory assets = IVault(vault).assets();
        uint[] memory amountsToDeposit = new uint[](1);
        amountsToDeposit[0] = amount;

        // ----------------------------- Prepare amount on user's balance
        _dealAndApprove(user, vault, assets, amountsToDeposit);
        // console.log("Deposit to vault", assets[0], amounts_[0]);

        uint balanceBefore = IVault(vault).balanceOf(user);

        // ----------------------------- Try to deposit assets to the vault
        vm.prank(user);
        IStabilityVault(vault).depositAssets(assets, amountsToDeposit, 0, user);

        return (amountsToDeposit[0], IVault(vault).balanceOf(user) - balanceBefore);
    }

    function _withdrawFromVault(address vault, uint value, address user) internal returns (uint withdrawn) {
        address[] memory _assets = IVault(vault).assets();

        uint balanceBefore = IERC20(_assets[0]).balanceOf(user);

        vm.prank(user);
        IStabilityVault(vault).withdrawAssets(_assets, value, new uint[](1));

        return IERC20(_assets[0]).balanceOf(user) - balanceBefore;
    }

    function _dealAndApprove(address user, address spender, address[] memory assets, uint[] memory amounts) internal {
        for (uint j; j < assets.length; ++j) {
            deal(assets[j], user, amounts[j]);

            vm.prank(user);
            IERC20(assets[j]).approve(spender, amounts[j]);
        }
    }

    function _upgradeStrategy(address strategyAddress) internal {
        address strategyImplementation = address(new AaveLeverageMerklFarmStrategy());

        IFactory factory = IFactory(IPlatform(PlasmaConstantsLib.PLATFORM).factory());

        vm.prank(PlasmaConstantsLib.MULTISIG);
        factory.setStrategyImplementation(StrategyIdLib.AAVE_LEVERAGE_MERKL_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }
}
