// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IStabilityDaoToken is IERC20, IERC20Metadata {
    /// @notice See https://stabilitydao.gitbook.io/stability/stability-dao/governance#current-parameters
    struct DaoParams {
        /// @notice Minimal amount of xSTBL tokens required to have STBLDAO tokens, decimals 18
        uint minimalPower;
        /// @notice xSTBL instant exit penalty, i.e. 50_00 = 50%
        uint exitPenalty;
        /// @notice TODO i.e. 100_000
        uint proposalThreshold;
        /// @notice Inter-chain power allocation delay, i.e. 1 day
        uint powerAllocationDelay;
    }

    //region --------------------------------------- Read functions
    /// @notice Current DAO config
    function config() external view returns (DaoParams memory);

    /// @notice Address of xSTBL token
    function xStbl() external view returns (address);

    /// @notice Address of xStaking contract
    function xStaking() external view returns (address);

    /// @notice TODO
    function minimalPower() external view returns (uint);

    /// @notice TODO
    function exitPenalty() external view returns (uint);

    /// @notice TODO
    function proposalThreshold() external view returns (uint);

    /// @notice TODO
    function powerAllocationDelay() external view returns (uint);

    //endregion --------------------------------------- Read functions

    //region --------------------------------------- Write functions
    /// @dev Init
    function initialize(address platform_, address xStbl_, address xStaking_, DaoParams memory config_) external;

    /// @notice Update DAO config
    /// XStaking.syncStabilityDaoTokenBalances() must be called after changing of minimalPower value
    /// @custom:restricted To multisig
    function updateConfig(DaoParams memory p) external;

    /// @custom:restricted To xStaking
    function mint(address account, uint amount) external;

    /// @custom:restricted To xStaking
    function burn(address account, uint amount) external;
    //endregion --------------------------------------- Write functions
}
