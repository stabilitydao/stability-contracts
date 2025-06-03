// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {VaultTypeLib} from "../core/libs/VaultTypeLib.sol";
import {IAggregatorInterfaceMinimal} from "../integrations/chainlink/IAggregatorInterfaceMinimal.sol";
import {IStabilityVault} from "../interfaces/IStabilityVault.sol";
import {IWrappedMetaVault} from "../interfaces/IWrappedMetaVault.sol";
import {IPriceReader} from "../interfaces/IPriceReader.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";

/// @title Minimal Chainlink-compatible Wrapped MetaVault price feed
/// @author Alien Deployer (https://github.com/a17)
contract WrappedMetaVaultOracle is IAggregatorInterfaceMinimal {
    address public immutable wrappedMetaVault;

    error NotTrustedPrice(address asset);

    //slither-disable-next-line missing-zero-check
    constructor(address wrappedMetaVault_) {
        wrappedMetaVault = wrappedMetaVault_;
    }

    /// @inheritdoc IAggregatorInterfaceMinimal
    function latestAnswer() external view returns (int) {
        address _wrappedMetaVault = wrappedMetaVault;
        address metaVault = IWrappedMetaVault(_wrappedMetaVault).metaVault();
        uint oneWrapperShare = 10 ** IERC20Metadata(_wrappedMetaVault).decimals();
        uint wrapperSharePriceNotNormalized = IERC4626(_wrappedMetaVault).convertToAssets(oneWrapperShare);
        bool isMultiVault = _eq(IStabilityVault(metaVault).vaultType(), VaultTypeLib.MULTIVAULT);
        if (isMultiVault) {
            address _asset = IERC4626(_wrappedMetaVault).asset();
            IPlatform platform = IPlatform(IControllable(_wrappedMetaVault).platform());
            (uint assetPrice, bool trusted) = IPriceReader(platform.priceReader()).getPrice(_asset);
            require(trusted, NotTrustedPrice(_asset));
            return int(wrapperSharePriceNotNormalized * assetPrice / oneWrapperShare / 1e10);
        }
        (uint metaVaultPrice, bool isMetaVaultPrice) = IStabilityVault(metaVault).price();
        require(isMetaVaultPrice, NotTrustedPrice(metaVault));
        return int(wrapperSharePriceNotNormalized * metaVaultPrice / oneWrapperShare / 1e10);
    }

    /// @inheritdoc IAggregatorInterfaceMinimal
    function decimals() external pure returns (uint8) {
        return 8;
    }

    function _eq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
