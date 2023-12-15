// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

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

    //region ----- Constants -----

    /// @dev Version of PriceReader implementation
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.PriceReader")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant PRICEREADER_STORAGE_LOCATION =
        0x5fb640640fb9e5b309b8dbb32d70e4c1afbc916914ea7278d067186632e15f00;

    //endregion ----- Constants -----

    //region ----- Storage -----

    /// @custom:storage-location erc7201:stability.PriceReader
    struct PriceReaderStorage {
        EnumerableSet.AddressSet _adapters;
    }

    //endregion ----- Storage -----

    function initialize(address platform_) public initializer {
        __Controllable_init(platform_);
    }

    /// @inheritdoc IPriceReader
    function addAdapter(address adapter_) external onlyOperator {
        PriceReaderStorage storage $ = _getStorage();
        if (!$._adapters.add(adapter_)) {
            revert AlreadyExist();
        }
        emit AdapterAdded(adapter_);
    }

    function removeAdapter(address adapter_) external onlyOperator {
        PriceReaderStorage storage $ = _getStorage();
        if (!$._adapters.remove(adapter_)) {
            revert NotExist();
        }
        emit AdapterRemoved(adapter_);
    }

    /// @inheritdoc IPriceReader
    //slither-disable-next-line calls-loop
    function getPrice(address asset) public view returns (uint price, bool trusted) {
        PriceReaderStorage storage $ = _getStorage();
        address[] memory __adapters = $._adapters.values();
        uint len = __adapters.length;
        // nosemgrep
        for (uint i; i < len; ++i) {
            //slither-disable-next-line unused-return
            (uint _price,) = IOracleAdapter(__adapters[i]).getPrice(asset);
            if (_price > 0) {
                return (_price, true);
            }
        }

        if (len > 0) {
            ISwapper swapper = ISwapper(IPlatform(platform()).swapper());
            // nosemgrep
            for (uint j; j < len; ++j) {
                IOracleAdapter oracleAdapter = IOracleAdapter($._adapters.at(j));
                address[] memory oracleAssets = oracleAdapter.assets();
                // nosemgrep
                uint oracleAssetsLen = oracleAssets.length;
                // nosemgrep
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
        // nosemgrep
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

    function adaptersLength() external view returns (uint) {
        PriceReaderStorage storage $ = _getStorage();
        return $._adapters.length();
    }

    //region ----- Internal logic -----

    function _getStorage() private pure returns (PriceReaderStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := PRICEREADER_STORAGE_LOCATION
        }
    }

    //endregion ----- Internal logic -----
}
