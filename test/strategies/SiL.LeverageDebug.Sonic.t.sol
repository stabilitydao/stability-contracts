// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IControllable} from "../../src/interfaces/IControllable.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {Vm, console, Test} from "forge-std/Test.sol";
import {SiloLeverageStrategy} from "../../src/strategies/SiloLeverageStrategy.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";
import {CommonLib} from "../../src/core/libs/CommonLib.sol";

contract SiloLeverageLendingStrategyDebugTest is Test {
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    //address public constant STRATEGY = 0x811002015AC45D551A3D962d8375A7B16Dede6BE; // S-stS
    address public constant STRATEGY = 0xfF9C35acDA4b136F71B1736B2BDFB5479f111C4A; // stS-S
    address public vault;
    address public multisig;
    IFactory public factory;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        vault = IStrategy(STRATEGY).vault();
        multisig = IPlatform(IControllable(STRATEGY).platform()).multisig();
        factory = IFactory(IPlatform(IControllable(STRATEGY).platform()).factory());
        //console.logBytes4(type(ILeverageLendingStrategy).interfaceId);
    }

    function testSiloDepositWithdrawUsersImpact() internal {
        address user1 = address(1);
        address user2 = address(2);
        uint user1Deposit = 100e18;
        uint user2Deposit = 1_000e18;

        uint originOracleSharePrice = _getOracledSharePrice();

        _depositForUser(user1, user1Deposit);
        assertEq(originOracleSharePrice, _getOracledSharePrice());

        _depositForUser(user2, user2Deposit);
        assertEq(originOracleSharePrice, _getOracledSharePrice());

        _depositForUser(user2, user2Deposit);
        assertEq(originOracleSharePrice, _getOracledSharePrice());

        vm.roll(block.number + 6);
        _withdrawAllForUser(user2);
        assertEq(originOracleSharePrice, _getOracledSharePrice());

        _withdrawAllForUser(user1);
        assertEq(originOracleSharePrice, _getOracledSharePrice());
    }

    function _getOracledSharePrice() internal view returns (uint) {
        return IStrategy(STRATEGY).total() * 1e18 / IERC20(vault).totalSupply();
    }

    function testSiLHardWork() internal {
        vm.recordLogs();
        vm.prank(vault);
        IStrategy(STRATEGY).doHardWork();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint j = 0; j < entries.length; ++j) {
            if (
                entries[j].topics[0]
                    == keccak256("LeverageLendingHardWork(int256,int256,uint256,uint256,uint256,uint256,uint256)")
            ) {
                (int realApr,,,,,,) = abi.decode(entries[j].data, (int, int, uint, uint, uint, uint, uint));
                console.log(string.concat("    Real APR: ", CommonLib.formatAprInt(realApr), "."));
            }
        }
    }

    /*function testSiLRebalanceDebt() public {
        ILeverageLendingStrategy s = ILeverageLendingStrategy(STRATEGY);
        (uint ltv,,,,,) = s.health();
        console.log('LTV', ltv);

        vm.startPrank(multisig);

        uint newLtv = 9490;
        console.log('New LTV', newLtv);
        uint resultLtv = s.rebalanceDebt(newLtv);
        console.log('Result LTV', resultLtv);
    }*/

    function _depositForUser(address user, uint depositAmount) internal {
        address[] memory assets = IStrategy(STRATEGY).assets();
        deal(assets[0], user, depositAmount);
        vm.startPrank(user);
        IERC20(assets[0]).approve(vault, depositAmount);
        uint[] memory amounts = new uint[](1);
        amounts[0] = depositAmount;
        IVault(vault).depositAssets(assets, amounts, 0, user);
        vm.stopPrank();
    }

    function _deposit(uint depositAmount) internal {
        address[] memory assets = IStrategy(STRATEGY).assets();
        deal(assets[0], address(this), depositAmount);
        IERC20(assets[0]).approve(vault, depositAmount);
        uint[] memory amounts = new uint[](1);
        amounts[0] = depositAmount;
        IVault(vault).depositAssets(assets, amounts, 0, address(this));
    }

    function _withdrawAllForUser(address user) internal {
        address[] memory assets = IStrategy(STRATEGY).assets();
        uint bal = IERC20(vault).balanceOf(user);
        vm.prank(user);
        IVault(vault).withdrawAssets(assets, bal, new uint[](1));
    }

    function _withdrawAll() internal {
        address[] memory assets = IStrategy(STRATEGY).assets();
        uint bal = IERC20(vault).balanceOf(address(this));
        IVault(vault).withdrawAssets(assets, bal, new uint[](1));
    }

    function _upgrade() internal {
        address strategyImplementation = address(new SiloLeverageStrategy());
        factory.setStrategyImplementation(StrategyIdLib.SILO_LEVERAGE, strategyImplementation);
        factory.upgradeStrategyProxy(STRATEGY);
    }
}
