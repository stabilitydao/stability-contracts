// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./base/Controllable.sol";
import "../interfaces/IPriceReader.sol";
import "../interfaces/IOracleAdapter.sol";
import "../interfaces/ISwapper.sol";

/// @dev Combining oracle and DeX spot prices
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// @author JodsMigel (https://github.com/JodsMigel)
contract PriceReader is Controllable, IPriceReader {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Version of PriceReader implementation
    string public constant VERSION = '1.0.0';

    EnumerableSet.AddressSet internal _adapters;

    /// @dev This empty reserved space is put in place to allow future versions to add new.
    /// variables without shifting down storage in the inheritance chain.
    /// Total gap == 50 - storage slots used.
    uint[50 - 2] private __gap;

    function initialize(address platform_) public initializer {
        __Controllable_init(platform_);
    }

    /// @inheritdoc IPriceReader
    function addAdapter(address adapter_) external onlyOperator {
        require(_adapters.add(adapter_), "PR: exist");
        emit AdapterAdded(adapter_);
    }

    function removeAdapter(address adapter_) external onlyOperator {
        require(_adapters.remove(adapter_), "PR: not exist");
        emit AdapterRemoved(adapter_);
    }

    /// @inheritdoc IPriceReader
    function getPrice(address asset) public view returns (uint price, bool trusted) {
        address[] memory __adapters = _adapters.values();
        uint len = __adapters.length;

        for (uint i; i < len; ++i) {
            //slither-disable-next-line unused-return
            (uint _price,) = IOracleAdapter(__adapters[i]).getPrice(asset);
            if (_price > 0) {
                return (_price, true);
            }
        }

        if (len > 0) {
            ISwapper swapper = ISwapper(IPlatform(platform()).swapper());

            for (uint j; j < len; ++j) {
                IOracleAdapter oracleAdapter = IOracleAdapter(_adapters.at(j));
                address[] memory oracleAssets = oracleAdapter.assets();
                uint oracleAssetsLen = oracleAssets.length;
                for (uint i; i < oracleAssetsLen; ++i) {
                    uint swapperPrice = swapper.getPrice(asset, oracleAssets[i], 0);
                    if (swapperPrice > 0) {
                        //slither-disable-next-line unused-return
                        (uint _price,) = oracleAdapter.getPrice(oracleAssets[i]);
                        uint assetOutDecimals = IERC20Metadata(oracleAssets[i]).decimals();
                        uint priceInTermOfOracleAsset;
                        if (assetOutDecimals <= 18) {
                            priceInTermOfOracleAsset = swapperPrice * 10 ** (18 - assetOutDecimals);
                        } else {
                            priceInTermOfOracleAsset = swapperPrice / 10 ** (assetOutDecimals - 18);
                        } 
                        return (priceInTermOfOracleAsset * _price / 1e18, false);
                    }
                }
            }
        }

        return (0, false);
    }

    /// @inheritdoc IPriceReader
    function getAssetsPrice(address[] memory assets_, uint[] memory amounts_) external view returns (uint total, uint[] memory assetAmountPrice, bool trusted) {
        uint len = assets_.length;
        bool notTrustedPrices;
        assetAmountPrice = new uint[](len);
        for (uint i; i < len; ++i) {
            (uint price, bool _trusted) = getPrice(assets_[i]);
            if (!_trusted) {
                notTrustedPrices = true;
            }
            uint decimals = IERC20Metadata(assets_[i]).decimals();
            if(decimals <= 18){
                assetAmountPrice[i] = amounts_[i] * 10 ** (18 - decimals)  * price / 1e18;
                total += assetAmountPrice[i];
            } else {
                assetAmountPrice[i] = amounts_[i] * price / 10**decimals;
                total += assetAmountPrice[i];
            }
        }
        trusted = !notTrustedPrices;
    }

    function adapters() external view returns(address[] memory) {
        return _adapters.values();
    }

    function adaptersLength() external view returns(uint) {
        return _adapters.length();
    }
}
