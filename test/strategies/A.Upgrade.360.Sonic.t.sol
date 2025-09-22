// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IMetaVault, IStabilityVault} from "../../src/core/vaults/MetaVault.sol";
import {SonicConstantsLib} from "../../chains/sonic/SonicConstantsLib.sol";
import {IPlatform} from "../../src/interfaces/IPlatform.sol";
import {IMetaVaultFactory} from "../../src/interfaces/IMetaVaultFactory.sol";
import {IFactory} from "../../src/interfaces/IFactory.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {IStrategy} from "../../src/interfaces/IStrategy.sol";
import {IAToken} from "../../src/integrations/aave/IAToken.sol";
import {IPriceReader} from "../../src/interfaces/IPriceReader.sol";
import {AaveStrategy} from "../../src/strategies/AaveStrategy.sol";
import {StrategyIdLib} from "../../src/strategies/libs/StrategyIdLib.sol";

/// @notice #360 - Add support of underlying operations to Aave strategy
contract AUpgrade360Test is Test {
    uint public constant FORK_BLOCK = 41821241; // Aug-06-2025 04:09:40 AM +UTC
    address public constant PLATFORM = SonicConstantsLib.PLATFORM;
    IMetaVault public metaVault;
    IMetaVaultFactory public metaVaultFactory;
    address public multisig;
    IPriceReader public priceReader;

    constructor() {
        vm.selectFork(vm.createFork(vm.envString("SONIC_RPC_URL"), FORK_BLOCK));

        metaVault = IMetaVault(SonicConstantsLib.METAVAULT_METAUSDC);
        metaVaultFactory = IMetaVaultFactory(IPlatform(PLATFORM).metaVaultFactory());
        multisig = IPlatform(PLATFORM).multisig();

        priceReader = IPriceReader(IPlatform(PLATFORM).priceReader());
    }

    /// @notice Try to deposit/withdraw underlying from the vault with Aave strategy
    function testUnderlyingOperations() public {
        IVault vault = IVault(SonicConstantsLib.VAULT_C_USDC_STABILITY_STABLEJACK);
        IStrategy strategy = vault.strategy();
        address[] memory assets = vault.assets();
        uint amount = 1000 * 10 ** IERC20Metadata(assets[0]).decimals();

        // ------------------- upgrade strategy
        _upgradeAaveStrategy(address(strategy));

        vm.prank(multisig);
        AaveStrategy(address(strategy)).setUnderlying();

        IAToken aToken = IAToken(AaveStrategy(address(strategy)).underlying());
        assertNotEq(address(aToken), address(0), "Underlying should not be zero address");

        // ------------------- deposit asset
        (uint deposited,) = _depositToVault(strategy, amount);
        assertEq(aToken.balanceOf(address(this)), 0, "Underlying should not be on the strategy balance 1");
        assertEq(deposited, amount, "Deposited amount should be equal to the given amount");
        // console.log("Deposited amount:", deposited);

        // ------------------- withdraw underlying
        address[] memory underlying = new address[](1);
        underlying[0] = address(aToken);

        uint balance = vault.balanceOf(address(this));
        vault.withdrawAssets(underlying, balance, new uint[](1));
        assertGt(aToken.balanceOf(address(this)), 0, "Underlying should be on the strategy balance");
        // console.log("Underlying balance after withdraw:", aToken.balanceOf(address(this)));

        // ------------------- deposit underlying
        uint[] memory underlyingAmounts = new uint[](1);
        underlyingAmounts[0] = aToken.balanceOf(address(this));

        IERC20(address(aToken)).approve(address(vault), underlyingAmounts[0]);
        vault.depositAssets(underlying, underlyingAmounts, 0, address(this));

        assertEq(aToken.balanceOf(address(this)), 0, "Underlying should not be on the strategy balance 2");

        // ------------------- withdraw asset
        uint withdrawn = _withdrawFromVault(strategy, vault.balanceOf(address(this)));
        // console.log("Withdrawn amount:", withdrawn);

        assertGe(
            IERC20(assets[0]).balanceOf(address(this)),
            amount,
            "Withdrawn amount should be at least the deposited amount 1"
        );
        assertEq(
            withdrawn,
            IERC20(assets[0]).balanceOf(address(this)),
            "Withdrawn amount should be equal to the current asset balance"
        );
    }

    //region ------------------------------ Auxiliary Functions
    function _upgradeAaveStrategy(address strategyAddress) internal {
        IFactory factory = IFactory(IPlatform(PLATFORM).factory());

        address strategyImplementation = address(new AaveStrategy());
        vm.prank(multisig);
        factory.setStrategyImplementation(StrategyIdLib.AAVE, strategyImplementation);

        factory.upgradeStrategyProxy(strategyAddress);
    }

    function _depositToVault(IStrategy strategy, uint amount_) internal returns (uint deposited, uint values) {
        address vault = strategy.vault();
        address[] memory assets = IVault(vault).assets();

        uint[] memory amounts_ = new uint[](assets.length);
        amounts_[0] = amount_;

        // ----------------------------- Prepare amount on user's balance
        _dealAndApprove(address(this), vault, assets, amounts_);

        // ----------------------------- Try to deposit assets to the vault
        uint valuesBefore = IERC20(vault).balanceOf(address(this));

        vm.prank(address(this));
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
    //endregion ------------------------------ Auxiliary Functions
}
