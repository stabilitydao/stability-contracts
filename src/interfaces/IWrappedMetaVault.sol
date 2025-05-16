// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IWrappedMetaVault is IERC4626 {
    /// @custom:storage-location erc7201:stability.WrappedMetaVault
    struct WrappedMetaVaultStorage {
        address metaVault;
        bool isMulti;
    }

    /// @dev Init
    function initialize(address platform_, address metaVault) external;

    /// @notice Address of MetaVault wrapped by this contract
    function metaVault() external view returns (address);
}
