// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Controllable, IPlatform} from "./base/Controllable.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";
import {IOracleAdapter} from "../interfaces/IOracleAdapter.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";
import {IStabilityVault} from "../interfaces/IStabilityVault.sol";

/// @dev Combining oracle and DeX spot prices
/// Changelog:
///     1.2.0: Implement transient cache for asset and vault prices - #348
///     1.1.0: IPriceReader.getVaultPrice; IPriceReader.vaultsWithSafeSharePrice
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
contract PriceReader is Controllable, IPriceReader {
    using EnumerableSet for EnumerableSet.AddressSet;

    //region ---------------------------- Constants

    /// @dev Version of PriceReader implementation
    string public constant VERSION = "1.2.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.PriceReader")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant PRICEREADER_STORAGE_LOCATION =
        0x5fb640640fb9e5b309b8dbb32d70e4c1afbc916914ea7278d067186632e15f00;

    error NotWhitelistedTransientCache();

    //endregion ---------------------------- Constants

    //region ---------------------------- Storage

    /// @custom:storage-location erc7201:stability.PriceReader
    struct PriceReaderStorage {
        EnumerableSet.AddressSet _adapters;
        EnumerableSet.AddressSet safeSharePrice;
        /// @notice Users allowed to use transient cache
        EnumerableSet.AddressSet whitelistTransientCache;
    }

    //endregion ---------------------------- Storage

    //region ---------------------------- Transient cache
    /// @dev Transient cache allows to cache price of single asset (wrapped meta vault)
    /// @dev and multiple prices of vaults (all sub-vaults of the given meta vault).

    /// @dev Number of _priceXXX and _addrXXX variables
    uint public constant MAX_COUNT_VAULT_PRICES_CACHED = 20;

    /// @notice Last cacheable asset for which the price was fetched
    address internal transient lastCacheableAsset;

    /// @notice Last trusted cacheable price for the lastCacheableAsset
    uint internal transient lastCacheablePrice;

    /// @notice Last cacheable trusted flag for lastCacheablePrice
    bool internal transient lastCacheableTrusted;

    /// @notice Count of busy _priceXXX and _addrXXX variables
    uint internal transient _countVaults;

    /// @notice Safety mask for the _priceXXX
    uint internal transient _safetyMask;

    uint internal transient _price00;
    uint internal transient _price01;
    uint internal transient _price02;
    uint internal transient _price03;
    uint internal transient _price04;
    uint internal transient _price05;
    uint internal transient _price06;
    uint internal transient _price07;
    uint internal transient _price08;
    uint internal transient _price09;
    uint internal transient _price10;
    uint internal transient _price11;
    uint internal transient _price12;
    uint internal transient _price13;
    uint internal transient _price14;
    uint internal transient _price15;
    uint internal transient _price16;
    uint internal transient _price17;
    uint internal transient _price18;
    uint internal transient _price19;

    address internal transient _addr00;
    address internal transient _addr01;
    address internal transient _addr02;
    address internal transient _addr03;
    address internal transient _addr04;
    address internal transient _addr05;
    address internal transient _addr06;
    address internal transient _addr07;
    address internal transient _addr08;
    address internal transient _addr09;
    address internal transient _addr10;
    address internal transient _addr11;
    address internal transient _addr12;
    address internal transient _addr13;
    address internal transient _addr14;
    address internal transient _addr15;
    address internal transient _addr16;
    address internal transient _addr17;
    address internal transient _addr18;
    address internal transient _addr19;
    //endregion ---------------------------- Transient cache

    //region ---------------------------- Initialization and modifiers
    function initialize(address platform_) public initializer {
        __Controllable_init(platform_);
    }

    function requireWhitelistTransientCache() internal view {
        // console.log("requireWhitelistTransientCache", msg.sender, address(this));
        require(_getStorage().whitelistTransientCache.contains(msg.sender), NotWhitelistedTransientCache());
    }
    //endregion ---------------------------- Initialization and modifiers

    //region ---------------------------- Restricted actions
    /// @inheritdoc IPriceReader
    function addAdapter(address adapter_) external onlyOperator {
        PriceReaderStorage storage $ = _getStorage();
        if (!$._adapters.add(adapter_)) {
            revert AlreadyExist();
        }
        emit AdapterAdded(adapter_);
    }

    /// @inheritdoc IPriceReader
    function removeAdapter(address adapter_) external onlyOperator {
        PriceReaderStorage storage $ = _getStorage();
        if (!$._adapters.remove(adapter_)) {
            revert NotExist();
        }
        emit AdapterRemoved(adapter_);
    }

    /// @inheritdoc IPriceReader
    function addSafeSharePrices(address[] memory vaults) external onlyOperator {
        PriceReaderStorage storage $ = _getStorage();
        uint len = vaults.length;
        for (uint i; i < len; ++i) {
            if (!$.safeSharePrice.add(vaults[i])) {
                revert AlreadyExist();
            }
            emit VaultWithSafeSharePriceAdded(vaults[i]);
        }
    }

    /// @inheritdoc IPriceReader
    function removeSafeSharePrices(address[] memory vaults) external onlyOperator {
        PriceReaderStorage storage $ = _getStorage();
        uint len = vaults.length;
        for (uint i; i < len; ++i) {
            if (!$.safeSharePrice.remove(vaults[i])) {
                revert NotExist();
            }
            emit VaultWithSafeSharePriceRemoved(vaults[i]);
        }
    }

    /// @inheritdoc IPriceReader
    function changeWhitelistTransientCache(address user, bool add) external onlyOperator {
        PriceReaderStorage storage $ = _getStorage();
        if (add) {
            //slither-disable-next-line unused-return
            $.whitelistTransientCache.add(user);
        } else {
            //slither-disable-next-line unused-return
            $.whitelistTransientCache.remove(user);
        }
    }

    /// @inheritdoc IPriceReader
    function preCalculatePriceTx(address asset) external {
        requireWhitelistTransientCache();

        if (asset == address(0)) {
            lastCacheableAsset = address(0);
        } else if (asset != lastCacheableAsset) {
            // no restrictions - anyone can call this function
            PriceReaderStorage storage $ = _getStorage();
            (uint price, bool trusted) = _getPrice($, asset);

            if (price != 0) {
                lastCacheableAsset = asset;
                lastCacheablePrice = price;
                lastCacheableTrusted = trusted;
            }
        }
    }

    /// @inheritdoc IPriceReader
    function preCalculateVaultPriceTx(address vault) external {
        requireWhitelistTransientCache();

        if (vault == address(0)) {
            _countVaults = 0;
        } else {
            PriceReaderStorage storage $ = _getStorage();
            (,, bool found) = _getVaultPriceFromCache(vault);
            if (!found) {
                _preCalculateVaultPriceTx($, vault);
            }
        }
    }

    //endregion ---------------------------- Restricted actions

    //region ---------------------------- View
    /// @inheritdoc IPriceReader
    //slither-disable-next-line calls-loop
    function getPrice(address asset) public view returns (uint price, bool trusted) {
        PriceReaderStorage storage $ = _getStorage();
        (price, trusted) =
            lastCacheableAsset == asset ? (lastCacheablePrice, lastCacheableTrusted) : _getPrice($, asset);
    }

    /// @inheritdoc IPriceReader
    function getVaultPrice(address vault) external view returns (uint price, bool safe) {
        PriceReaderStorage storage $ = _getStorage();
        (uint priceFromCache, bool safeFromCache, bool found) = _getVaultPriceFromCache(vault);
        (price, safe) = found ? (priceFromCache, safeFromCache) : _getVaultPrice($, vault);
    }

    /// @inheritdoc IPriceReader
    function getAssetsPrice(
        address[] memory assets_,
        uint[] memory amounts_
    ) external view returns (uint total, uint[] memory assetAmountPrice, uint[] memory assetPrice, bool trusted) {
        uint len = assets_.length;
        //slither-disable-next-line uninitialized-local
        bool notTrustedPrices;
        assetAmountPrice = new uint[](len);
        assetPrice = new uint[](len);
        bool _trusted;
        for (uint i; i < len; ++i) {
            (assetPrice[i], _trusted) = getPrice(assets_[i]);
            if (!_trusted) {
                notTrustedPrices = true;
            }
            //slither-disable-next-line calls-loop
            uint decimals = IERC20Metadata(assets_[i]).decimals();
            if (decimals <= 18) {
                assetAmountPrice[i] = amounts_[i] * 10 ** (18 - decimals) * assetPrice[i] / 1e18;
                total += assetAmountPrice[i];
            } else {
                assetAmountPrice[i] = amounts_[i] * assetPrice[i] / 10 ** decimals;
                total += assetAmountPrice[i];
            }
        }
        trusted = !notTrustedPrices;
    }

    function adapters() external view returns (address[] memory) {
        PriceReaderStorage storage $ = _getStorage();
        return $._adapters.values();
    }

    /// @inheritdoc IPriceReader
    function vaultsWithSafeSharePrice() external view returns (address[] memory vaults) {
        PriceReaderStorage storage $ = _getStorage();
        return $.safeSharePrice.values();
    }

    function adaptersLength() external view returns (uint) {
        PriceReaderStorage storage $ = _getStorage();
        return $._adapters.length();
    }

    function whitelistTransientCache(address user_) external view returns (bool) {
        PriceReaderStorage storage $ = _getStorage();
        return $.whitelistTransientCache.contains(user_);
    }
    //endregion ---------------------------- View

    //region ---------------------------- Internal logic

    function _getStorage() private pure returns (PriceReaderStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := PRICEREADER_STORAGE_LOCATION
        }
    }

    function _getPrice(PriceReaderStorage storage $, address asset) internal view returns (uint price, bool trusted) {
        address[] memory __adapters = $._adapters.values();
        uint len = __adapters.length;
        for (uint i; i < len; ++i) {
            //slither-disable-next-line low-level-calls
            //slither-disable-next-line unused-return
            (uint _price,) = IOracleAdapter(__adapters[i]).getPrice(asset);
            if (_price > 0) {
                return (_price, true);
            }
        }

        if (len > 0) {
            ISwapper swapper = ISwapper(IPlatform(platform()).swapper());
            for (uint j; j < len; ++j) {
                IOracleAdapter oracleAdapter = IOracleAdapter($._adapters.at(j));
                //slither-disable-next-line low-level-calls
                address[] memory oracleAssets = oracleAdapter.assets();
                uint oracleAssetsLen = oracleAssets.length;
                for (uint i; i < oracleAssetsLen; ++i) {
                    //slither-disable-next-line low-level-calls
                    uint swapperPrice = swapper.getPrice(asset, oracleAssets[i], 0);
                    if (swapperPrice > 0) {
                        //slither-disable-next-line low-level-calls
                        //slither-disable-next-line unused-return
                        (uint _price,) = oracleAdapter.getPrice(oracleAssets[i]);
                        //slither-disable-next-line low-level-calls
                        uint assetOutDecimals = IERC20Metadata(oracleAssets[i]).decimals();
                        uint priceInTermOfOracleAsset;
                        if (assetOutDecimals <= 18) {
                            priceInTermOfOracleAsset = swapperPrice * 10 ** (18 - assetOutDecimals);
                        } else {
                            //slither-disable-next-line divide-before-multiply
                            priceInTermOfOracleAsset = swapperPrice / 10 ** (assetOutDecimals - 18);
                        }
                        return (priceInTermOfOracleAsset * _price / 1e18, false);
                    }
                }
            }
        }

        return (0, false);
    }

    function _getVaultPrice(
        PriceReaderStorage storage $,
        address vault
    ) internal view returns (uint price, bool safe) {
        bool safeSharePrice = $.safeSharePrice.contains(vault);
        (uint vaultOnChainPrice, bool trustedAssetPrice) = IStabilityVault(vault).price();
        if (safeSharePrice) {
            // console.log("getVaultPrice.vault.1", temp - gasleft());
            return (vaultOnChainPrice, trustedAssetPrice);
        }

        // todo get vault price from internal oracle and return as safe
        // ...

        return (vaultOnChainPrice, false);
    }

    //endregion ---------------------------- Internal logic

    //region ------------------------- Transient cache internal logic
    function _getVaultPriceFromCache(address vault_) internal view returns (uint price, bool safe, bool found) {
        uint count = _countVaults;
        if (count != 0) {
            // we don't use nested ifs here to avoid problems with forge formatter
            if (_addr00 == vault_) return (_price00, _getSafe(0), true);
            if (count == 1) return (0, false, false);
            if (_addr01 == vault_) return (_price01, _getSafe(1), true);
            if (count == 2) return (0, false, false);
            if (_addr02 == vault_) return (_price02, _getSafe(2), true);
            if (count == 3) return (0, false, false);
            if (_addr03 == vault_) return (_price03, _getSafe(3), true);
            if (count == 4) return (0, false, false);
            if (_addr04 == vault_) return (_price04, _getSafe(4), true);
            if (count == 5) return (0, false, false);
            if (_addr05 == vault_) return (_price05, _getSafe(5), true);
            if (count == 6) return (0, false, false);
            if (_addr06 == vault_) return (_price06, _getSafe(6), true);
            if (count == 7) return (0, false, false);
            if (_addr07 == vault_) return (_price07, _getSafe(7), true);
            if (count == 8) return (0, false, false);
            if (_addr08 == vault_) return (_price08, _getSafe(8), true);
            if (count == 9) return (0, false, false);
            if (_addr09 == vault_) return (_price09, _getSafe(9), true);
            if (count == 10) return (0, false, false);
            if (_addr10 == vault_) return (_price10, _getSafe(10), true);
            if (count == 11) return (0, false, false);
            if (_addr11 == vault_) return (_price11, _getSafe(11), true);
            if (count == 12) return (0, false, false);
            if (_addr12 == vault_) return (_price12, _getSafe(12), true);
            if (count == 13) return (0, false, false);
            if (_addr13 == vault_) return (_price13, _getSafe(13), true);
            if (count == 14) return (0, false, false);
            if (_addr14 == vault_) return (_price14, _getSafe(14), true);
            if (count == 15) return (0, false, false);
            if (_addr15 == vault_) return (_price15, _getSafe(15), true);
            if (count == 16) return (0, false, false);
            if (_addr16 == vault_) return (_price16, _getSafe(16), true);
            if (count == 17) return (0, false, false);
            if (_addr17 == vault_) return (_price17, _getSafe(17), true);
            if (count == 18) return (0, false, false);
            if (_addr18 == vault_) return (_price18, _getSafe(18), true);
            if (count == 19) return (0, false, false);
            if (_addr19 == vault_) return (_price19, _getSafe(19), true);
        }
        return (0, false, false);
    }

    function _preCalculateVaultPriceTx(PriceReaderStorage storage $, address vault) internal {
        uint count = _countVaults;
        if (count < MAX_COUNT_VAULT_PRICES_CACHED) {
            (uint price, bool safe) = _getVaultPrice($, vault);
            if (count == 0) (_price00, _addr00) = (price, vault);
            if (count == 1) (_price01, _addr01) = (price, vault);
            if (count == 2) (_price02, _addr02) = (price, vault);
            if (count == 3) (_price03, _addr03) = (price, vault);
            if (count == 4) (_price04, _addr04) = (price, vault);
            if (count == 5) (_price05, _addr05) = (price, vault);
            if (count == 6) (_price06, _addr06) = (price, vault);
            if (count == 7) (_price07, _addr07) = (price, vault);
            if (count == 8) (_price08, _addr08) = (price, vault);
            if (count == 9) (_price09, _addr09) = (price, vault);
            if (count == 10) (_price10, _addr10) = (price, vault);
            if (count == 11) (_price11, _addr11) = (price, vault);
            if (count == 12) (_price12, _addr12) = (price, vault);
            if (count == 13) (_price13, _addr13) = (price, vault);
            if (count == 14) (_price14, _addr14) = (price, vault);
            if (count == 15) (_price15, _addr15) = (price, vault);
            if (count == 16) (_price16, _addr16) = (price, vault);
            if (count == 17) (_price17, _addr17) = (price, vault);
            if (count == 18) (_price18, _addr18) = (price, vault);
            if (count == 19) (_price19, _addr19) = (price, vault);
            _setSafe(count, safe);
            ++_countVaults;
        }
    }

    function _setSafe(uint index, bool safe) internal {
        _safetyMask = (_safetyMask & ~(1 << index)) | (safe ? (1 << index) : 0);
    }

    function _getSafe(uint index) internal view returns (bool safe) {
        return (_safetyMask & (1 << index)) != 0;
    }
    //endregion ------------------------- Transient cache internal logic
}
