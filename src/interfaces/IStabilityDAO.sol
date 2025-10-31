// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IStabilityDAO is IERC20, IERC20Metadata {
    /// @notice Parameters of Stability DAO
    /// @dev For details see https://stabilitydao.gitbook.io/stability/stability-dao/governance#current-parameters
    struct DaoParams {
        /// @notice Minimal amount of xSTBL tokens required to have STBL_DAO tokens, decimals 18
        uint minimalPower;
        /// @notice xSTBL instant exit penalty, decimals 1e4, i.e. 50_00 = 50%
        /// Set 0 to use default value XSTBL.DEFAULT_SLASHING_PENALTY
        uint exitPenalty;
        /// @notice Min percent of power that a user should have to be able to create new proposal. Decimals 1e5, i.e. 50_000 = 50%
        uint proposalThreshold;
        /// @notice A percent of votes required to reach quorum for a proposal. Decimals 1e5, i.e. 20_000 = 20%
        /// If the total number of votes is less than this percent, proposal is rejected
        uint quorum;
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

    /// @notice Minimal amount of xSTBL tokens required to have STBL_DAO tokens, decimals 18
    function minimalPower() external view returns (uint);

    /// @notice xSTBL instant exit penalty (slashing penalty), decimals 1e4, i.e. 50_00 = 50%
    function exitPenalty() external view returns (uint);

    /// @notice Min percent of power that a user should have to be able to create a new proposal, decimals 1e5, i.e. 50_000 = 50%
    function proposalThreshold() external view returns (uint);

    /// @notice A percent of votes required to reach quorum for a proposal, decimals 1e5, i.e. 20_000 = 20%
    /// If the total number of votes is less than this percent, proposal is rejected
    function quorum() external view returns (uint);

    /// @notice Inter-chain power allocation delay, i.e. 1 day
    function powerAllocationDelay() external view returns (uint);

    /// @notice Get total power of a user.
    /// The power = user's own (not-delegated) balance of STBL_DAO + balances of all users that delegated to him
    /// If user has balance of staked xSTBL below minimalPower, his power is 0
    function getVotes(address user_) external view returns (uint);

    /// @notice Get delegation info of a user
    /// @return delegatedTo The address to whom the user has delegated his voting power (or address(0) if not delegated)
    /// @return delegators The list of addresses that have delegated their voting power to the user
    function delegates(address user_) external view returns (address delegatedTo, address[] memory delegators);

    //endregion --------------------------------------- Read functions

    //region --------------------------------------- Write functions
    /// @dev Init
    function initialize(address platform_, address xStbl_, address xStaking_, DaoParams memory config_) external;

    /// @notice Update DAO config
    /// XStaking.syncStabilityDAOBalances() must be called after changing of minimalPower value
    /// @custom:restricted To multisig or governance
    function updateConfig(DaoParams memory p) external;

    /// @custom:restricted To xStaking
    function mint(address account, uint amount) external;

    /// @custom:restricted To xStaking
    function burn(address account, uint amount) external;

    /// @notice Delegate all voting power to another user.
    /// To remove delegation just delegate the power to yourself or to address(0).
    /// @custom:restricted Anyone can call this function
    function setPowerDelegation(address to) external;

    //endregion --------------------------------------- Write functions
}
