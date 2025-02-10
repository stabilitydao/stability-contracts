// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ISilo} from "./ISilo.sol";

interface ISiloConfig {
    /// @notice Retrieves the silo ID
    /// @dev Each silo is assigned a unique ID. ERC-721 token is minted with identical ID to deployer.
    /// An owner of that token receives the deployer fees.
    /// @return siloId The ID of the silo
    function SILO_ID() external view returns (uint256 siloId); // solhint-disable-line func-name-mixedcase
}