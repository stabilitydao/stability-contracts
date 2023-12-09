// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "./base/Controllable.sol";
import "../interfaces/IAprOracle.sol";

/// @dev This oracle is needed to obtain auto compound APR of underlying assets in an on-chain environment.
///      These APRs are usually accessible from the protocol APIs.
///      Such data is needed on-chain for the operation of automatic vaults,
///      which can themselves select assets to work with, and to show the overall APR of the strategy in VaultManager NFT.
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
contract AprOracle is Controllable, IAprOracle {
    //region ----- Storage -----

    /// @custom:storage-location erc7201:stability.AprOracle
    struct AprOracleStorage {
        mapping(address asset => uint apr) assetApr;
    }

    //region ----- Storage -----

    //region ----- Constants -----

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.AprOracle")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant APRORACLE_STORAGE_LOCATION =
        0x0dc0ce6c496f1b862d4b48237a101bb40130a02088e33738cbe0a34f7cf84300;

    //region ----- Constants -----

    function initialize(address platform_) external initializer {
        __Controllable_init(platform_);
    }

    /// @inheritdoc IAprOracle
    function setAprs(address[] memory assets, uint[] memory aprs) external onlyOperator {
        AprOracleStorage storage $ = _getStorage();
        uint len = assets.length;
        if (len != aprs.length) {
            revert IControllable.IncorrectArrayLength();
        }
        // nosemgrep
        for (uint i; i < len; ++i) {
            $.assetApr[assets[i]] = aprs[i];
        }
        emit SetAprs(assets, aprs);
    }

    /// @inheritdoc IAprOracle
    function getAprs(address[] memory assets) external view returns (uint[] memory aprs) {
        AprOracleStorage storage $ = _getStorage();
        uint len = assets.length;
        aprs = new uint[](len);
        // nosemgrep
        for (uint i; i < len; ++i) {
            aprs[i] = $.assetApr[assets[i]];
        }
    }

    //region ----- Internal logic -----

    function _getStorage() private pure returns (AprOracleStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := APRORACLE_STORAGE_LOCATION
        }
    }

    //endregion ----- Internal logic -----
}
