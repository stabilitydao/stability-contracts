// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Controllable} from "../core/base/Controllable.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IStabilityDAO} from "../interfaces/IStabilityDAO.sol";
import {IXStaking} from "../interfaces/IXStaking.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IXSTBL} from "../interfaces/IXSTBL.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Staking contract for xSTBL
/// Inspired by VoteModule from Ramses/Shadow codebase
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// Changelog:
///  1.2.0: Integration with STBLDAO
///  1.0.1: use SafeERC20.safeTransfer/safeTransferFrom instead of ERC20 transfer/transferFrom
contract XStaking is Controllable, ReentrancyGuardUpgradeable, IXStaking {
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.2.0";

    /// @notice decimal precision of 1e18
    uint public constant PRECISION = 10 ** 18;

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.XStaking")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant XSTAKING_STORAGE_LOCATION =
        0x53928b797321282c691925ff3a5fd3453fa9ad1f6652f05af4268a4c997e9d00;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.XStaking
    struct XStakingStorage {
        /// @inheritdoc IXStaking
        address xSTBL;
        /// @inheritdoc IXStaking
        uint totalSupply;
        /// @inheritdoc IXStaking
        uint lastUpdateTime;
        /// @inheritdoc IXStaking
        uint rewardPerTokenStored;
        /// @inheritdoc IXStaking
        uint periodFinish;
        /// @inheritdoc IXStaking
        uint rewardRate;
        /// @inheritdoc IXStaking
        uint duration;
        /// @inheritdoc IXStaking
        mapping(address user => uint rewards) storedRewardsPerUser;
        /// @inheritdoc IXStaking
        mapping(address user => uint rewardPerToken) userRewardPerTokenStored;
        /// @inheritdoc IXStaking
        mapping(address user => uint amount) balanceOf;
    }

    error StabilityDaoNotInitialized();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function initialize(address platform_, address xSTBL_) external initializer {
        __Controllable_init(platform_);
        __ReentrancyGuard_init();
        XStakingStorage storage $ = _getXStakingStorage();
        $.xSTBL = xSTBL_;
        $.duration = 30 minutes;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev common multirewarder-esque modifier for updating on interactions
    modifier updateReward(address account) {
        _updateReward(account);
        _;
    }

    //region ----------------------------------- Restricted actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IXStaking
    function setNewDuration(uint newDuration) external onlyGovernanceOrMultisig {
        XStakingStorage storage $ = _getXStakingStorage();
        uint oldDuration = $.duration;
        $.duration = newDuration;
        emit NewDuration(oldDuration, newDuration);
    }

    /// @inheritdoc IXStaking
    function syncStabilityDAOBalances(address[] calldata users) external onlyGovernanceOrMultisig {
        XStakingStorage storage $ = _getXStakingStorage();
        IStabilityDAO stabilityDao = getStabilityDAO();
        require(address(stabilityDao) != address(0), StabilityDaoNotInitialized());

        // @dev assume here that 1 STBL_DAO = 1 staked xSTBL always
        uint threshold = stabilityDao.minimalPower();

        uint len = users.length;
        for (uint i; i < len; ++i) {
            _syncUser($, stabilityDao, users[i], threshold);
        }
    }

    //endregion ----------------------------------- Restricted actions

    //region ----------------------------------- User actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       USER ACTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IXStaking
    function depositAll() external {
        deposit(IERC20(xSTBL()).balanceOf(msg.sender));
    }

    /// @inheritdoc IXStaking
    function deposit(uint amount) public updateReward(msg.sender) nonReentrant {
        /// @dev ensure the amount is > 0
        require(amount != 0, IncorrectZeroArgument());

        XStakingStorage storage $ = _getXStakingStorage();

        /// @dev transfer xSTBL in
        // slither-disable-next-line unchecked-transfer
        IERC20($.xSTBL).safeTransferFrom(msg.sender, address(this), amount);

        /// @dev update accounting
        $.totalSupply += amount;
        $.balanceOf[msg.sender] += amount;

        /// @dev sync STBLDAO balances
        _syncDaoTokensToBalance($, msg.sender);

        emit Deposit(msg.sender, amount);
    }

    /// @inheritdoc IXStaking
    function getReward() external updateReward(msg.sender) nonReentrant {
        /// @dev claim all the rewards
        _claim(msg.sender);
    }

    /// @inheritdoc IXStaking
    function withdrawAll() external {
        XStakingStorage storage $ = _getXStakingStorage();
        /// @dev withdraw the stored balance
        withdraw($.balanceOf[msg.sender]);
        /// @dev claim rewards for the user
        _claim(msg.sender);
    }

    /// @inheritdoc IXStaking
    function withdraw(uint amount) public updateReward(msg.sender) nonReentrant {
        /// @dev ensure the amount is > 0
        require(amount != 0, IncorrectZeroArgument());

        XStakingStorage storage $ = _getXStakingStorage();

        /// @dev reduce total "supply"
        $.totalSupply -= amount;

        /// @dev decrement from balance mapping
        $.balanceOf[msg.sender] -= amount;

        /// @dev transfer the xSTBL to the caller
        // slither-disable-next-line unchecked-transfer
        IERC20($.xSTBL).safeTransfer(msg.sender, amount);

        /// @dev sync STBLDAO balances
        _syncDaoTokensToBalance($, msg.sender);

        emit Withdraw(msg.sender, amount);
    }

    /// @inheritdoc IXStaking
    function notifyRewardAmount(uint amount) external updateReward(address(0)) nonReentrant {
        /// @dev ensure > 0
        require(amount != 0, IncorrectZeroArgument());

        XStakingStorage storage $ = _getXStakingStorage();

        address _xSTBL = $.xSTBL;

        /// @dev only callable by xSTBL and RevenueRouter contract
        require(msg.sender == _xSTBL || msg.sender == IXSTBL(_xSTBL).revenueRouter(), IncorrectMsgSender());

        /// @dev take the STBL from a contract to the XStaking
        // slither-disable-next-line unchecked-transfer
        IERC20(IXSTBL(_xSTBL).STBL()).safeTransferFrom(msg.sender, address(this), amount);

        uint _periodFinish = $.periodFinish;
        uint _duration = $.duration;

        if (block.timestamp >= _periodFinish) {
            /// @dev the new reward rate being the amount divided by the duration
            $.rewardRate = amount / _duration;
        } else {
            /// @dev remaining seconds until the period finishes
            uint remaining = _periodFinish - block.timestamp;
            /// @dev remaining tokens to stream via t * rate
            uint _left = remaining * $.rewardRate;
            /// @dev update the rewardRate to the notified amount plus what is left, divided by the duration
            $.rewardRate = (amount + _left) / _duration;
        }

        /// @dev update timestamp for the rebase
        $.lastUpdateTime = block.timestamp;
        /// @dev update periodFinish (when all rewards are streamed)
        $.periodFinish = block.timestamp + _duration;

        emit NotifyReward(msg.sender, amount);
    }

    //endregion ----------------------------------- User actions

    //region ----------------------------------- View functions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IXStaking
    function lastTimeRewardApplicable() public view returns (uint) {
        return Math.min(block.timestamp, _getXStakingStorage().periodFinish);
    }

    /// @inheritdoc IXStaking
    function xSTBL() public view returns (address) {
        return _getXStakingStorage().xSTBL;
    }

    /// @inheritdoc IXStaking
    function totalSupply() external view returns (uint) {
        return _getXStakingStorage().totalSupply;
    }

    /// @inheritdoc IXStaking
    function lastUpdateTime() external view returns (uint) {
        return _getXStakingStorage().lastUpdateTime;
    }

    /// @inheritdoc IXStaking
    function rewardPerTokenStored() external view returns (uint) {
        return _getXStakingStorage().rewardPerTokenStored;
    }

    /// @inheritdoc IXStaking
    function periodFinish() external view returns (uint) {
        return _getXStakingStorage().periodFinish;
    }

    /// @inheritdoc IXStaking
    function rewardRate() external view returns (uint) {
        return _getXStakingStorage().rewardRate;
    }

    /// @inheritdoc IXStaking
    function duration() external view returns (uint) {
        return _getXStakingStorage().duration;
    }

    /// @inheritdoc IXStaking
    function storedRewardsPerUser(address user) external view returns (uint) {
        return _getXStakingStorage().storedRewardsPerUser[user];
    }

    /// @inheritdoc IXStaking
    function userRewardPerTokenStored(address user) external view returns (uint) {
        return _getXStakingStorage().userRewardPerTokenStored[user];
    }

    /// @inheritdoc IXStaking
    function balanceOf(address user) external view returns (uint) {
        return _getXStakingStorage().balanceOf[user];
    }

    /// @inheritdoc IXStaking
    function rewardPerToken() public view returns (uint) {
        XStakingStorage storage $ = _getXStakingStorage();
        uint _totalSupply = $.totalSupply;
        return
        /// @dev if there's no staked xSTBL
        _totalSupply == 0
            /// @dev return the existing value
            ? $.rewardPerTokenStored
            /// @dev else add the existing value
            : $.rewardPerTokenStored
                /// @dev to remaining time (since update) multiplied by the current reward rate
                /// @dev scaled to precision of 1e18, then divided by the total supply
                + (lastTimeRewardApplicable() - $.lastUpdateTime) * $.rewardRate * PRECISION / _totalSupply;
    }

    /// @inheritdoc IXStaking
    function earned(address account) public view returns (uint) {
        XStakingStorage storage $ = _getXStakingStorage();
        return
        /// @dev the vote balance of the account
        (($.balanceOf[account]
                    /// @dev current global reward per token, subtracted from the stored reward per token for the user
                    * (rewardPerToken() - $.userRewardPerTokenStored[account]))
                /// @dev divide by the 1e18 precision
                / PRECISION)
            /// @dev add the existing stored rewards for the account to the total
            + $.storedRewardsPerUser[account];
    }

    //endregion ----------------------------------- View functions

    //region ----------------------------------- Internal logic
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev Sync balance of Stability DAO token according to the current user's balance of xSTBL
    /// after depositing or withdrawing xSTBL
    function _syncDaoTokensToBalance(XStakingStorage storage $, address user_) internal {
        IStabilityDAO daoToken = getStabilityDAO();
        if (address(daoToken) != address(0)) {
            // @dev assume here that 1 STBL_DAO = 1 staked xSTBL always
            uint threshold = daoToken.minimalPower();

            _syncUser($, daoToken, user_, threshold);
        }
    }

    /// @dev Sync balance of Stability DAO token for a specific user according to his current power
    /// @param stabilityDao Address of the STBL_DAO token
    /// @param user_ Address of the user to sync
    /// @param threshold Minimal amount of staked xSTBL tokens required to have STBL_DAO
    function _syncUser(XStakingStorage storage $, IStabilityDAO stabilityDao, address user_, uint threshold) internal {
        uint balanceStakedXStbl = $.balanceOf[user_];

        /// @dev if user has too few xSTBL staked, their STBL_DAO balance will be 0
        /// @dev otherwise user should receive 1 STBL_DAO for each 1 staked xSTBL
        uint toMint = balanceStakedXStbl < threshold ? 0 : balanceStakedXStbl;
        uint balanceStabilityDao = IERC20(stabilityDao).balanceOf(user_);

        if (toMint > balanceStabilityDao) {
            /// @dev mint the difference
            stabilityDao.mint(user_, toMint - balanceStabilityDao);
        } else if (balanceStabilityDao > toMint) {
            /// @dev burn the difference
            stabilityDao.burn(user_, balanceStabilityDao - toMint);
        }
    }

    /// @dev common multirewarder-esque modifier for updating on interactions
    function _updateReward(address account) internal {
        XStakingStorage storage $ = _getXStakingStorage();

        /// @dev fetch and store the new rewardPerToken
        $.rewardPerTokenStored = rewardPerToken();
        /// @dev fetch and store the new last update time
        $.lastUpdateTime = lastTimeRewardApplicable();
        /// @dev check for address(0) calls from notifyRewardAmount
        if (account != address(0)) {
            /// @dev update the individual account's mapping for stored rewards
            $.storedRewardsPerUser[account] = earned(account);
            /// @dev update account's mapping for rewardsPerTokenStored
            $.userRewardPerTokenStored[account] = $.rewardPerTokenStored;
        }
    }

    /// @dev internal claim function to make exiting and claiming easier
    function _claim(address user) internal {
        XStakingStorage storage $ = _getXStakingStorage();

        /// @dev fetch the stored rewards (updated by modifier)
        uint reward = $.storedRewardsPerUser[user];
        if (reward > 0) {
            /// @dev zero out the stored rewards
            $.storedRewardsPerUser[user] = 0;

            address _xSTBL = $.xSTBL;
            address stbl = IXSTBL(_xSTBL).STBL();

            /// @dev approve STBL to xSTBL
            IERC20(stbl).approve(_xSTBL, reward);

            /// @dev convert
            IXSTBL(_xSTBL).enter(reward);

            /// @dev transfer xSTBL to the user
            // slither-disable-next-line unchecked-transfer
            IERC20(_xSTBL).safeTransfer(user, reward);

            emit ClaimRewards(user, reward);
        }
    }

    function _getXStakingStorage() internal pure returns (XStakingStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := XSTAKING_STORAGE_LOCATION
        }
    }

    function getStabilityDAO() internal view returns (IStabilityDAO) {
        return IStabilityDAO(IPlatform(IControllable(address(this)).platform()).stabilityDAO());
    }

    //endregion ----------------------------------- Internal logic
}
