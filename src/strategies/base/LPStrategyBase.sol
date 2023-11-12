// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./StrategyBase.sol";
import "../libs/LPStrategyLib.sol";
import "../../interfaces/ILPStrategy.sol";

/// @dev Base liquidity providing strategy
/// @author Alien Deployer (https://github.com/a17)
abstract contract LPStrategyBase is StrategyBase, ILPStrategy {

    /// @dev Version of LPStrategyBase implementation
    string public constant VERSION_LP_STRATEGY_BASE = '1.0.0';

    address public pool;
    IDexAdapter public dexAdapter;
    uint[] internal _feesOnBalance;

    /// @dev This empty reserved space is put in place to allow future versions to add new.
    /// variables without shifting down storage in the inheritance chain.
    /// Total gap == 50 - storage slots used.
    uint[50 - 3] private __gap;

    function __LPStrategyBase_init(LPStrategyBaseInitParams memory params) internal onlyInitializing {
        address[] memory _assets;
        uint exchangeAssetIndex;
        (_assets, exchangeAssetIndex, dexAdapter) = LPStrategyLib.LPStrategyBase_init(params.platform, params, dexAdapterId());
        _feesOnBalance = new uint[](_assets.length);
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

    /// @inheritdoc ILPStrategy
    function dexAdapterId() public view virtual returns(string memory);

    function _previewDepositAssets(uint[] memory amountsMax) internal view virtual override returns (uint[] memory amountsConsumed, uint value) {
        (value, amountsConsumed) = dexAdapter.getLiquidityForAmounts(pool, amountsMax);
    }

    function _previewDepositAssets(address[] memory assets_, uint[] memory amountsMax) internal view override returns (uint[] memory amountsConsumed, uint value) {
        LPStrategyLib.checkPreviewDepositAssets(assets_, _assets, amountsMax);
        return _previewDepositAssets(amountsMax);
    }

    function _withdrawAssets(address[] memory assets_, uint value, address receiver) internal virtual override returns (uint[] memory amountsOut) {
        LPStrategyLib.checkAssets(assets_, _assets);
        return _withdrawAssets(value, receiver);
    }

    function _processRevenue(address[] memory assets_, uint[] memory amountsRemaining) internal override returns (bool needCompound) {
        return LPStrategyLib.processRevenue(platform(), vault, dexAdapter, _exchangeAssetIndex, pool, assets_, amountsRemaining);
    }

    function _swapForDepositProportion(uint prop0Pool) internal returns(uint[] memory amountsToDeposit) {
        return LPStrategyLib.swapForDepositProportion(platform(), dexAdapter, pool, _assets, prop0Pool);
    }
}
