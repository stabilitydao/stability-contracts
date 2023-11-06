// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "./base/Controllable.sol";
import "../interfaces/IAprOracle.sol";

/// @dev This oracle is needed to obtain auto compound APR of underlying assets in an on-chain environment.
///      These APRs are usually accessible from the protocol APIs.
///      Such data is needed on-chain for the operation of automatic vaults,
///      which can themselves select assets to work with, and to show the overall APR of the strategy in VaultManager NFT.
/// @author Alien Deployer (https://github.com/a17)
contract AprOracle is Controllable, IAprOracle {

    /// @dev Version of AprOracle implementation
    string public constant VERSION = '1.0.0';

    mapping (address asset => uint apr) public assetApr;

    function initialize(address platform_) external initializer {
        __Controllable_init(platform_);
    }

    /// @inheritdoc IAprOracle
    function setAprs(address[] memory assets, uint[] memory aprs) external onlyOperator {
        uint len = assets.length;
        require (len == aprs.length, "AprOracle: mismatch");
        for (uint i; i < len; ++i) {
            assetApr[assets[i]] = aprs[i];
        }
    }

    /// @inheritdoc IAprOracle
    function getAprs(address[] memory assets) external view returns (uint[] memory aprs) {
        uint len = assets.length;
        aprs = new uint[](len);
        for (uint i; i < len; ++i) {
            aprs[i] = assetApr[assets[i]];
        }
    }
}
