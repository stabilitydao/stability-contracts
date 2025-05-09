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

contract SiLUpgradeTest2 is Test {
    address public constant PLATFORM = 0x4Aca671A420eEB58ecafE83700686a2AD06b20D8;

    /// @notice Stability stS Silo Leverage 3 wS x17.4
    address public constant VAULT1 = 0x709833e5B4B98aAb812d175510F94Bc91CFABD89;

    /// @notice Stability wS Silo Leverage 3 stS x17.4
    address public constant VAULT2 = 0x2fBeBA931563feAAB73e8C66d7499c49c8AdA224;

    address public constant BEETS_VAULT_V3 = 0xbA1333333333a1BA1108E8412f11850A5C319bA9;

    address public constant SHADOW_POOL_S_STS = 0xde861c8Fc9AB78fE00490C5a38813D26e2d09C95;

    uint internal constant FLASH_LOAN_KIND_BALANCER_V3 = 1;
    uint internal constant FLASH_LOAN_KIND_UNISWAP_V3 = 2;

    address public multisig;
    IFactory public factory;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL")));
        // vm.rollFork(16296000); // Mar-27-2025 08:48:46 AM +UTC
        vm.rollFork(25503966); // May-09-2025 12:31:34 PM +UTC

        factory = IFactory(IPlatform(PLATFORM).factory());
        multisig = IPlatform(PLATFORM).multisig();
    }

    /// @notice Check flash loan through BEETS
    function testSiLUpgrade1() public {
        address user1 = address(1);

        vm.prank(multisig);
        address vault = VAULT2;
        address strategyAddress = address(IVault(vault).strategy());

        // ----------------- deploy new impl and upgrade
        _upgradeStrategy(strategyAddress);

        SiloLeverageStrategy strategy = SiloLeverageStrategy(payable(strategyAddress));
        vm.stopPrank();

        // ----------------- use flash loan through Balancer v3
        _setFlashLoanVault(strategy, BEETS_VAULT_V3, uint(ILeverageLendingStrategy.FlashLoanKind.BalancerV3_1));

        // ----------------- check current state
        address collateralAsset = IStrategy(strategyAddress).assets()[0];

        // ----------------- deposit & withdraw
        _depositForUser(vault, strategyAddress, user1, 1_00e18);
        vm.roll(block.number + 6);
        _withdrawAllForUser(vault, strategyAddress, user1);

        // ----------------- check results
        console.log(_getDiffPercent(IERC20(collateralAsset).balanceOf(user1), 1_00e18));
        assertLe(_getDiffPercent(IERC20(collateralAsset).balanceOf(user1), 1_00e18), 200); // 2%
    }

    /// @notice Check flash loan through Uniswap
    function testSiLUpgrade2() public {
        address user1 = address(1);

        vm.prank(multisig);
        address vault = VAULT1;
        address strategyAddress = address(IVault(vault).strategy());

        // ----------------- deploy new impl and upgrade
        _upgradeStrategy(strategyAddress);

        SiloLeverageStrategy strategy = SiloLeverageStrategy(payable(strategyAddress));
        vm.stopPrank();

        // ----------------- use flash loan through Uniswap V3
        _setFlashLoanVault(strategy, SHADOW_POOL_S_STS, uint(ILeverageLendingStrategy.FlashLoanKind.UniswapV3_2));

        // ----------------- check current state
        address collateralAsset = IStrategy(strategyAddress).assets()[0];

        // ----------------- deposit & withdraw
        _depositForUser(vault, strategyAddress, user1, 1_000e18);
        vm.roll(block.number + 6);
        _withdrawAllForUser(vault, strategyAddress, user1);

        // ----------------- check results
        console.log(_getDiffPercent(IERC20(collateralAsset).balanceOf(user1), 1_000e18));
        assertLe(_getDiffPercent(IERC20(collateralAsset).balanceOf(user1), 1_000e18), 200); // 2%
    }

    //region -------------------------- Auxiliary functions

    function _showHealth(
        SiloLeverageStrategy strategy,
        string memory /*state*/
    ) internal view returns (uint) {
        //console.log(state);
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

    function _depositForUser(
        address vault,
        address strategy,
        address user,
        uint depositAmount
    ) internal returns (uint) {
        address[] memory assets = IStrategy(strategy).assets();
        //console.log("deal", depositAmount);
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

    function _withdrawForUser(address vault, address strategy, address user, uint /*amount*/ ) internal {
        /*console.log(
            "_withdrawForUser", amount, IERC20(vault).balanceOf(user), Math.min(amount, IERC20(vault).balanceOf(user))
        );*/
        address[] memory assets = IStrategy(strategy).assets();
        vm.prank(user);
        IVault(vault).withdrawAssets(
            assets,
            1e18, //Math.min(amount, IERC20(vault).balanceOf(user)),
            new uint[](1)
        );
    }

    function _setFlashLoanVault(SiloLeverageStrategy strategy, address vault, uint kind) internal {
        (uint[] memory params, address[] memory addresses) = strategy.getUniversalParams();
        params[10] = kind;
        addresses[0] = vault;

        vm.prank(multisig);
        strategy.setUniversalParams(params, addresses);
    }

    function _getDiffPercent(uint x, uint y) internal pure returns (uint) {
        return x > y ? (x - y) * 100_00 / x : (y - x) * 100_00 / x;
    }
    //endregion -------------------------- Auxiliary functions

}
