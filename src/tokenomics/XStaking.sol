// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Controllable} from "../core/base/Controllable.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IXStaking} from "../interfaces/IXStaking.sol";
import {IXSTBL} from "../interfaces/IXSTBL.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";

contract XStaking is Controllable, ReentrancyGuardUpgradeable, IXStaking {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.0.0";

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

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function initialize(address platform_, address xSTBL_) external initializer {
        __Controllable_init(platform_);
        __ReentrancyGuard_init();
        XStakingStorage storage $ = _getXStakingStorage();
        $.xSTBL = xSTBL_;
        $.duration = 1 days;
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         MODIFIERS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev common multirewarder-esque modifier for updating on interactions
    modifier updateReward(address account) {
        _updateReward(account);
        _;
    }

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
        IERC20($.xSTBL).transferFrom(msg.sender, address(this), amount);

        /// @dev update accounting
        $.totalSupply += amount;
        $.balanceOf[msg.sender] += amount;

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
        IERC20($.xSTBL).transfer(msg.sender, amount);

        emit Withdraw(msg.sender, amount);
    }

    /// @inheritdoc IXStaking
    function notifyRewardAmount(uint amount) external updateReward(address(0)) nonReentrant {
        /// @dev ensure > 0
        require(amount != 0, IncorrectZeroArgument());

        XStakingStorage storage $ = _getXStakingStorage();

        address _xSTBL = $.xSTBL;

        /// @dev only callable by xSTBL and RevenueRouter contract
        // todo RevenueRouter
        require(msg.sender == _xSTBL || IPlatform(platform()).isOperator(msg.sender), IncorrectMsgSender());

        /// @dev take the STBL from a contract to the XStaking
        IERC20(IXSTBL(_xSTBL).STBL()).transferFrom(msg.sender, address(this), amount);

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
        /// @dev the timestamp of when people can withdraw next
        /// @dev not DoSable because only xShadow can notify
        //unlockTime = cooldown + periodFinish;

        emit NotifyReward(msg.sender, amount);
    }

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
        (
            (
                $.balanceOf[account]
                /// @dev current global reward per token, subtracted from the stored reward per token for the user
                * (rewardPerToken() - $.userRewardPerTokenStored[account])
            )
            /// @dev divide by the 1e18 precision
            / PRECISION
        )
        /// @dev add the existing stored rewards for the account to the total
        + $.storedRewardsPerUser[account];
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

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
            IERC20(_xSTBL).transfer(user, reward);

            emit ClaimRewards(user, reward);
        }
    }

    function _getXStakingStorage() internal pure returns (XStakingStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := XSTAKING_STORAGE_LOCATION
        }
    }
}
