// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SonicSetup, SonicConstantsLib} from "../base/chains/SonicSetup.sol";
import {UniversalTest, StrategyIdLib} from "../base/UniversalTest.sol";
import {console, Test} from "forge-std/Test.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import "../../src/interfaces/IStrategy.sol";

contract AaveStrategyTestSonic is SonicSetup, UniversalTest {
    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        // vm.rollFork(22116484); // Apr-25-2025 01:47:21 AM +UTC
        vm.rollFork(28001684); // May-19-2025 01:21:46 PM +UTC
        allowZeroApr = true;
        duration1 = 0.1 hours;
        duration2 = 0.1 hours;
        duration3 = 0.1 hours;
    }

    function testAaveStrategy() public universalTest {
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_wS);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_USDC);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_scUSD);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_WETH);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_USDT);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_wOS);
        _addStrategy(SonicConstantsLib.STABILITY_SONIC_stS);
    }

    function _addStrategy(address aToken) internal {
        address[] memory initStrategyAddresses = new address[](1);
        initStrategyAddresses[0] = aToken;
        strategies.push(
            Strategy({
                id: StrategyIdLib.AAVE,
                pool: address(0),
                farmId: type(uint).max,
                strategyInitAddresses: initStrategyAddresses,
                strategyInitNums: new uint[](0)
            })
        );
    }

//    function _preDeposit() internal override {
//        console.log("!!!!!START!!!!!!", IStrategy(currentStrategy).description());
//        (string memory name,) = IStrategy(currentStrategy).getSpecificName();
//        console.log("!!!!!START4!!!!!!", name);
//
//        address user1 = address(1);
//        address user2 = address(2);
//
//        uint amount1 = 1000e18;
//        uint amount2 = 1500e18;
//
//        address vault = IStrategy(currentStrategy).vault();
//
//        console.log("!!!!!!!!!!!!! deposit user1", amount1);
//        console.log("balance vault user1", IERC20(vault).balanceOf(user1));
//        console.log("balance vault user2", IERC20(vault).balanceOf(user2));
//        uint deposited1 = _depositForUser(vault, user1, amount1);
//        vm.warp(block.timestamp + 9 hours);
//        vm.roll(block.number + 100_000);
//        {(uint tvl,) = IVault(vault).tvl(); console.log("Vault tvl", tvl);}
//        console.log("Vault total supply", IERC20(vault).totalSupply());
//
//        console.log("!!!!!!!!!!!!! deposit user2", amount2);
//        console.log("balance vault user1", IERC20(vault).balanceOf(user1));
//        console.log("balance vault user2", IERC20(vault).balanceOf(user2));
//        uint deposited2 = _depositForUser(vault, user2, amount2);
//        vm.warp(block.timestamp + 9 hours);
//        vm.roll(block.number + 100_000);
//        {(uint tvl,) = IVault(vault).tvl(); console.log("Vault tvl", tvl);}
//        console.log("Vault total supply", IERC20(vault).totalSupply());
//
//        console.log("!!!!!!!!!!!!! withdraw user1", IERC20(vault).balanceOf(user1));
//        console.log("balance vault user1", IERC20(vault).balanceOf(user1));
//        console.log("balance vault user2", IERC20(vault).balanceOf(user2));
//        uint withdrawn1 = _withdrawAllForUser(vault, currentStrategy, user1);
//        {(uint tvl,) = IVault(vault).tvl(); console.log("Vault tvl", tvl);}
//        console.log("Vault total supply", IERC20(vault).totalSupply());
//
//        console.log("!!!!!!!!!!!!! withdraw user2", IERC20(vault).balanceOf(user2));
//        console.log("balance vault user1", IERC20(vault).balanceOf(user1));
//        console.log("balance vault user2", IERC20(vault).balanceOf(user2));
//        uint withdrawn2 = _withdrawAllForUser(vault, currentStrategy, user2);
//
//        {(uint tvl,) = IVault(vault).tvl(); console.log("Vault tvl", tvl);}
//        console.log("Vault total supply", IERC20(vault).totalSupply());
//
//
//        console.log("deposited1", deposited1);
//        console.log("deposited2", deposited2);
//        console.log("withdrawn1", withdrawn1);
//        console.log("withdrawn2", withdrawn2);
//        console.log("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! FINISH");
//    }

    //region -------------------------- Deposit withdraw routines
    function _depositForUser(address vault, address user, uint depositAmount) internal returns (uint) {
        address[] memory assets = IStrategy(IVault(vault).strategy()).assets();

        // --------------------------- provide amount to the user
        deal(assets[0], user, depositAmount + IERC20(assets[0]).balanceOf(user));

        // --------------------------- deposit
        vm.startPrank(user);
        IERC20(assets[0]).approve(vault, depositAmount);
        uint[] memory amounts = new uint[](1);
        amounts[0] = depositAmount;
        IVault(vault).depositAssets(assets, amounts, 0, user);
        vm.stopPrank();

        return depositAmount;
    }

    function _withdrawAllForUser(address vault, address strategy, address user) internal returns (uint) {
        return _withdrawAmount(vault, strategy, user, IERC20(vault).balanceOf(user));
    }

    function _withdrawForUser(address vault, address strategy, address user, uint amount) internal returns (uint) {
        uint amountToWithdraw = Math.min(amount, IERC20(vault).balanceOf(user));
        return _withdrawAmount(vault, strategy, user, amountToWithdraw);
    }

    function _withdrawForUserPartly(
        address vault,
        address strategy,
        address user,
        uint percent
    ) internal returns (uint) {
        return _withdrawAmount(vault, strategy, user, IERC20(vault).balanceOf(user) * percent / 100);
    }

    function _withdrawAmount(address vault, address strategy, address user, uint amount) internal returns (uint) {
        // --------------------------- withdraw
        address[] memory assets = IStrategy(strategy).assets();
        uint balanceBefore = IERC20(assets[0]).balanceOf(user);

        vm.prank(user);
        IVault(vault).withdrawAssets(assets, amount, new uint[](1));

        uint withdrawn = IERC20(assets[0]).balanceOf(user) - balanceBefore;

        return withdrawn;
    }
    //endregion -------------------------- Deposit withdraw routines
}
