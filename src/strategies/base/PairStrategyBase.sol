// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./StrategyBase.sol";
import "../../interfaces/IPairStrategyBase.sol";
import "../../interfaces/IRVault.sol";

/// @dev Base strategy for a liquidity position made up of two ERC-20 tokens
/// @author Alien Deployer (https://github.com/a17)
abstract contract PairStrategyBase is StrategyBase, IPairStrategyBase {

    /// @dev Version of PairStrategyBase implementation
    string public constant VERSION_PAIR_STRATEGY_BASE = '1.0.0';

    address public pool;
    IDexAdapter public dexAdapter;
    uint internal _fee0OnBalance;
    uint internal _fee1OnBalance;

    /// @dev This empty reserved space is put in place to allow future versions to add new.
    /// variables without shifting down storage in the inheritance chain.
    /// Total gap == 50 - storage slots used.
    uint[50 - 4] private __gap;

    function __PairStrategyBase_init(PairStrategyBaseInitParams memory params) internal onlyInitializing {
        address[] memory _assets;
        uint exchangeAssetIndex;
        (_assets, exchangeAssetIndex, dexAdapter) = StrategyLib.PairStrategyBase_init(params.platform, params, dexAdapterId());
        __StrategyBase_init(params.platform, params.id, params.vault, _assets, params.underlying, exchangeAssetIndex);
        pool = params.pool;
    }

    /// @inheritdoc IStrategy
    function supportedVaultTypes() external view virtual override returns(string[] memory types) {
        types = new string[](3);
        types[0] = VaultTypeLib.COMPOUNDING;
        types[1] = VaultTypeLib.REWARDING;
        types[2] = VaultTypeLib.REWARDING_MANAGED;
    }

    /// @inheritdoc IPairStrategyBase
    function dexAdapterId() public view virtual returns(string memory);

    function _previewDepositAssets(uint[] memory amountsMax) internal view virtual override returns (uint[] memory amountsConsumed, uint value) {
        (value, amountsConsumed) = dexAdapter.getLiquidityForAmounts(pool, amountsMax);
    }

    function _previewDepositAssets(address[] memory assets_, uint[] memory amountsMax) internal view override returns (uint[] memory amountsConsumed, uint value) {
        StrategyLib.checkPairStrategyBasePreviewDepositAssets(assets_, _assets, amountsMax);
        return _previewDepositAssets(amountsMax);
    }

    function _withdrawAssets(address[] memory assets_, uint value, address receiver) internal virtual override returns (uint[] memory amountsOut) {
        StrategyLib.checkPairStrategyBaseWithdrawAssets(assets_, _assets);
        return _withdrawAssets(value, receiver);
    }

    function _processRevenue(address[] memory assets_, uint[] memory amountsRemaining) internal override returns (bool needCompound) {
        return StrategyLib.processRevenue(platform(), vault, dexAdapter, _exchangeAssetIndex, pool, assets_, amountsRemaining);
    }

    function _swapForDepositProportion(uint prop0Pool) internal returns(uint[] memory amountsToDeposit) {
        return StrategyLib.pairStrategyBaseSwapForDepositProportion(platform(), dexAdapter, pool, _assets, prop0Pool);
    }
}
