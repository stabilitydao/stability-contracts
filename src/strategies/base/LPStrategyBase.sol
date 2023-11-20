// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./StrategyBase.sol";
import "../libs/LPStrategyLib.sol";
import "../../interfaces/ILPStrategy.sol";

/// @dev Base liquidity providing strategy
/// @author Alien Deployer (https://github.com/a17)
/// @author JodsMigel (https://github.com/JodsMigel)
abstract contract LPStrategyBase is StrategyBase, ILPStrategy {

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Version of LPStrategyBase implementation
    string public constant VERSION_LP_STRATEGY_BASE = '1.0.0';

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.LPStrategyBase")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant LPSTRATEGYBASE_STORAGE_LOCATION = 0xa6fdc931ca23c69f54119a0a2d6478619b5aa365084590a1fbc287668fbabe00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          STORAGE                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    struct LPStrategyBaseStorage {
        /// @inheritdoc ILPStrategy
        address pool;
        /// @inheritdoc ILPStrategy
        IAmmAdapter ammAdapter;
        uint[] _feesOnBalance;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INITIALIZATION                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function __LPStrategyBase_init(LPStrategyBaseInitParams memory params) internal onlyInitializing {
        LPStrategyBaseStorage storage $ = _getLPStrategyBaseStorage();
        address[] memory _assets;
        uint exchangeAssetIndex;
        (_assets, exchangeAssetIndex, $.ammAdapter) = LPStrategyLib.LPStrategyBase_init(params.platform, params, ammAdapterId());
        $._feesOnBalance = new uint[](_assets.length);
        __StrategyBase_init(params.platform, params.id, params.vault, _assets, params.underlying, exchangeAssetIndex);
        $.pool = params.pool;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       VIEW FUNCTIONS                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(ILPStrategy).interfaceId || super.supportsInterface(interfaceId);
    }

    /// @inheritdoc IStrategy
    function supportedVaultTypes() external view virtual override returns(string[] memory types) {
        types = new string[](3);
        types[0] = VaultTypeLib.COMPOUNDING;
        types[1] = VaultTypeLib.REWARDING;
        types[2] = VaultTypeLib.REWARDING_MANAGED;
    }

    /// @inheritdoc ILPStrategy
    function ammAdapterId() public view virtual returns(string memory);

    /// @inheritdoc ILPStrategy
    function pool() public view override returns (address) {
        return _getLPStrategyBaseStorage().pool;
    }

    /// @inheritdoc ILPStrategy
    function ammAdapter() public view returns (IAmmAdapter) {
        return _getLPStrategyBaseStorage().ammAdapter;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _previewDepositAssets(uint[] memory amountsMax) internal view virtual override returns (uint[] memory amountsConsumed, uint value) {
        LPStrategyBaseStorage storage $ = _getLPStrategyBaseStorage();
        (value, amountsConsumed) = $.ammAdapter.getLiquidityForAmounts($.pool, amountsMax);
    }

    function _previewDepositAssets(address[] memory assets_, uint[] memory amountsMax) internal view override returns (uint[] memory amountsConsumed, uint value) {
        LPStrategyLib.checkPreviewDepositAssets(assets_, assets(), amountsMax);
        return _previewDepositAssets(amountsMax);
    }

    function _withdrawAssets(address[] memory assets_, uint value, address receiver) internal virtual override returns (uint[] memory amountsOut) {
        LPStrategyLib.checkAssets(assets_, assets());
        return _withdrawAssets(value, receiver);
    }

    function _processRevenue(address[] memory assets_, uint[] memory amountsRemaining) internal override returns (bool needCompound) {
        LPStrategyBaseStorage storage $ = _getLPStrategyBaseStorage();
        return LPStrategyLib.processRevenue(platform(), vault(), $.ammAdapter, _getStrategyBaseStorage()._exchangeAssetIndex, $.pool, assets_, amountsRemaining);
    }

    function _swapForDepositProportion(uint prop0Pool) internal returns(uint[] memory amountsToDeposit) {
        LPStrategyBaseStorage storage $ = _getLPStrategyBaseStorage();
        return LPStrategyLib.swapForDepositProportion(platform(), $.ammAdapter, $.pool, assets(), prop0Pool);
    }

    function _getLPStrategyBaseStorage() internal pure returns (LPStrategyBaseStorage storage $) {
        assembly {
            $.slot := LPSTRATEGYBASE_STORAGE_LOCATION
        }
    }
}
