// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IStabilityVault} from "../../src/core/vaults/MetaVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IAToken} from "../../src/integrations/aave/IAToken.sol";
import {IAavePoolConfigurator} from "../../src/integrations/aave/IAavePoolConfigurator.sol";
import {IAaveAddressProvider} from "../../src/integrations/aave/IAaveAddressProvider.sol";
import {IPool} from "../../src/integrations/aave/IPool.sol";
import {AaveMerklFarmStrategy} from "../../src/strategies/AaveMerklFarmStrategy.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";

/// @notice #360 - Add support of underlying operations to AaveMerklFarmStrategy strategy
contract AMFUpgrade429MaxDepositSonicTest is Test {
    uint public constant FORK_BLOCK = 54081591; // Nov-07-2025 03:37:58 AM +UTC

    address public multisig;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        multisig = IPlatform(SonicConstantsLib.PLATFORM).multisig();
    }

    function testMaxDepositLimitedSupplyCap() public {
        IVault vault = IVault(SonicConstantsLib.VAULT_C_STBL_USDC);
        IStrategy strategy = vault.strategy();

        // ------------------- upgrade strategy
        _upgradeAaveMerklFarmStrategy(address(strategy));

        vm.prank(multisig);
        AaveMerklFarmStrategy(address(strategy)).setUnderlying();

        // ------------------- get max deposit amount
        uint[] memory maxAmounts = vault.maxDeposit(address(this));
        assertEq(maxAmounts.length, 1, "maxDeposit length should be equal to assets length");
        assertNotEq(maxAmounts[0], type(uint).max, "max deposit is limited");

        // ------------------- it's not possible to deposit amount greater than maxDeposit
        {
            uint snapshot = vm.snapshotState();
            // max deposit has 1% margin, so we try to exceed it by 2%
            (, uint depositedValue) = _depositToVault(strategy, maxAmounts[0] * 102 / 100, true);
            assertEq(depositedValue, 0, "cannot deposit when exceeding maxDeposit");
            vm.revertToState(snapshot);
        }

        // ------------------- it's possible to deposit maxDeposit amount
        {
            uint snapshot = vm.snapshotState();
            (, uint depositedValue) = _depositToVault(strategy, maxAmounts[0], false);
            assertGt(depositedValue, 0, "maxDeposit amount was successfully deposited");

            uint[] memory maxAmountsAfter = vault.maxDeposit(address(this));
            assertApproxEqAbs(
                maxAmountsAfter[0], maxAmounts[0] / 100, maxAmounts[0] / 1000, "max deposit has 1% margin"
            );

            vm.revertToState(snapshot);
        }
    }

    function testMaxDepositUnlimitedSupplyCap() public {
        IVault vault = IVault(SonicConstantsLib.VAULT_C_STBL_USDC);
        IStrategy strategy = vault.strategy();

        {
            IAToken aToken = IAToken(AaveMerklFarmStrategy(address(strategy)).underlying());
            IAavePoolConfigurator poolConfigurator = IAavePoolConfigurator(
                IAaveAddressProvider(IPool(IAToken(aToken).POOL()).ADDRESSES_PROVIDER()).getPoolConfigurator()
            );
            address poolOwner = IAaveAddressProvider(IPool(IAToken(aToken).POOL()).ADDRESSES_PROVIDER()).owner();
            address underlying = aToken.UNDERLYING_ASSET_ADDRESS();

            vm.prank(poolOwner);
            poolConfigurator.setSupplyCap(underlying, 0);
        }

        // ------------------- upgrade strategy
        _upgradeAaveMerklFarmStrategy(address(strategy));

        vm.prank(multisig);
        AaveMerklFarmStrategy(address(strategy)).setUnderlying();

        // ------------------- get max deposit amount
        uint[] memory maxAmounts = vault.maxDeposit(address(this));
        assertEq(maxAmounts.length, 1, "maxDeposit length should be equal to assets length");
        assertEq(maxAmounts[0], type(uint).max, "max deposit is unlimited");

        // ------------------- it's possible to deposit very large amount
        {
            (, uint depositedValue) = _depositToVault(strategy, 1e10, false);
            assertGt(depositedValue, 0, "maxDeposit amount was successfully deposited");

            uint[] memory maxAmountsAfter = vault.maxDeposit(address(this));
            assertEq(maxAmountsAfter[0], type(uint).max, "max deposit is still unlimited");
        }
    }

    //region ------------------------------ Auxiliary Functions
    function _upgradeAaveMerklFarmStrategy(address strategyAddress) internal {
        IFactory factory = IFactory(IPlatform(SonicConstantsLib.PLATFORM).factory());

        address strategyImplementation = address(new AaveMerklFarmStrategy());
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.AAVE_MERKL_FARM, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _depositToVault(
        IStrategy strategy,
        uint amount_,
        bool shouldFail
    ) internal returns (uint deposited, uint values) {
        address vault = strategy.vault();
        address[] memory assets = IVault(vault).assets();

        uint[] memory amounts_ = new uint[](assets.length);
        amounts_[0] = amount_;

        // ----------------------------- Prepare amount on user's balance
        _dealAndApprove(address(this), vault, assets, amounts_);

        // ----------------------------- Try to deposit assets to the vault
        uint valuesBefore = IERC20(vault).balanceOf(address(this));

        vm.prank(address(this));
        if (shouldFail) {
            vm.expectRevert();
        }
        IStabilityVault(vault).depositAssets(assets, amounts_, 0, address(this));
        vm.roll(block.number + 6);

        return (amounts_[0], IERC20(vault).balanceOf(address(this)) - valuesBefore);
    }

    function _withdrawFromVault(IStrategy strategy, uint values) internal returns (uint withdrawn) {
        address vault = strategy.vault();
        address[] memory _assets = IVault(vault).assets();

        uint balanceBefore = IERC20(_assets[0]).balanceOf(address(this));

        vm.prank(address(this));
        IStabilityVault(vault).withdrawAssets(_assets, values, new uint[](1));
        vm.roll(block.number + 6);

        return IERC20(_assets[0]).balanceOf(address(this)) - balanceBefore;
    }

    function _dealAndApprove(address user, address spender, address[] memory assets, uint[] memory amounts) internal {
        for (uint j; j < assets.length; ++j) {
            deal(assets[j], user, amounts[j]);
            vm.prank(user);
            IERC20(assets[j]).approve(spender, amounts[j]);
        }
    }

    function _keepConsoleInImports() internal pure {
        console.log("hide warning");
    }
    //endregion ------------------------------ Auxiliary Functions
}
