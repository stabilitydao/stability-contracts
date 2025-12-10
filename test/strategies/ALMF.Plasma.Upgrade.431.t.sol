// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, Vm, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AaveLeverageMerklFarmStrategy} from "../../src/strategies/AaveLeverageMerklFarmStrategy.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IStabilityVault} from "../../src/interfaces/IStabilityVault.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IFarmingStrategy} from "../../src/interfaces/IFarmingStrategy.sol";
import {PlasmaConstantsLib} from "../../chains/plasma/PlasmaConstantsLib.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {AmmAdapterIdLib} from "../../src/adapters/libs/AmmAdapterIdLib.sol";
import {ALMFLib} from "../../src/strategies/libs/ALMFLib.sol";

/// @notice Add revenueBaseAssetIndex param to farm, reset share price
contract ALMFUpgrade431PlasmaTest is Test {
    uint internal constant FORK_BLOCK = 8423845; // Dec-10-2025 08:15:16 UTC

    /// @notice Stability weETH Aave Leverage Merkl Farm USDT0
    address internal constant VAULT = 0xab0087D6fbC877246A4Ba33636f80E5dCbd5BE01;

    address internal multisig;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("PLASMA_RPC_URL"), FORK_BLOCK));

        _upgradeStrategy(address(IVault(VAULT).strategy()));
    }

    function testUpgradeStrategy() public {
        IStrategy strategy = IVault(VAULT).strategy();

        // --------------------------------------------- Hardwork before reset
        deal(PlasmaConstantsLib.TOKEN_WXPL, address(strategy), 1e18); // emulate merkl rewards

        uint earned1 = _doHardWork(strategy);
        assertNotEq(earned1, 0, "earned 1");

        // --------------------------------------------- Change farm params and reset share price
        {
            IFactory factory = IFactory(IPlatform(PlasmaConstantsLib.PLATFORM).factory());
            uint farmId = IFarmingStrategy(address(strategy)).farmId();
            IFactory.Farm memory farm = factory.farm(farmId);
            assertEq(farm.nums.length, 4, "farm is not updated");
            uint[] memory nums = new uint[](5);
            for (uint i; i < 4; ++i) {
                nums[i] = farm.nums[i];
            }
            nums[4] = ALMFLib.REVENUE_BASE_ASSET_1; // 1 - revenue-base-asset is borrow asset
            farm.nums = nums;

            vm.prank(PlasmaConstantsLib.MULTISIG);
            factory.updateFarm(farmId, farm);
        }

        // --------------------------------------------- Reset internal share price
        vm.prank(IPlatform(PlasmaConstantsLib.PLATFORM).multisig());
        AaveLeverageMerklFarmStrategy(address(strategy)).resetSharePrice();
        skip(5 days);

        // --------------------------------------------- Hardwork after reset
        deal(PlasmaConstantsLib.TOKEN_WXPL, address(strategy), 1e18); // emulate merkl rewards

        uint earned2 = _doHardWork(strategy);
        assertNotEq(earned2, 0, "earned 2");
        skip(5 days);

        // --------------------------------------------- Next hardworks
        uint[] memory earned = new uint[](5);
        for (uint i; i < 5; ++i) {
            deal(PlasmaConstantsLib.TOKEN_WXPL, address(strategy), 1e18); // emulate merkl rewards

            earned[i] = _doHardWork(strategy);
            assertNotEq(earned[i], 0, "earned 3");
            skip(5 days);
        }

        // todo probably we need to compare here earned amounts with and without switching revenueBaseAssetIndex and resetting price
        //        console.log(earned1, earned2, earned[0], earned[1]);
        //        console.log(earned[2], earned[3], earned[4]);
    }

    function _doHardWork(IStrategy strategy) internal returns (uint earnedUSD18) {
        address vault = strategy.vault();

        vm.recordLogs();
        vm.prank(PlasmaConstantsLib.MULTISIG);
        IVault(vault).doHardWork();

        // extract data from event IStrategy.HardWork
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("HardWork(uint256,uint256,uint256,uint256,uint256,uint256,uint256[])");
        for (uint i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                (,, earnedUSD18,,,,) = abi.decode(logs[i].data, (uint, uint, uint, uint, uint, uint, uint[]));
                break;
            }
        }

        return earnedUSD18;
    }

    function _tryToDepositToVault(
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
