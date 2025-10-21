// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Controllable} from "../core/base/Controllable.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IXSTBL} from "../interfaces/IXSTBL.sol";
import {IXStaking} from "../interfaces/IXStaking.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IRevenueRouter} from "../interfaces/IRevenueRouter.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStabilityDAO} from "../interfaces/IStabilityDAO.sol";

/// @title xSTBL token
/// Inspired by xRAM/xSHADOW from Ramses/Shadow codebase
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// @author Omriss (https://github.com/omriss)
/// Changelog:
///  1.1.0: add possibility to change the slashing penalty value - #406
///  1.0.1: use SafeERC20.safeTransfer/safeTransferFrom instead of ERC20 transfer/transferFrom
contract XSTBL is Controllable, ERC20Upgradeable, IXSTBL {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.1.0";

    /// @inheritdoc IXSTBL
    uint public constant BASIS = 10_000;

    /// @notice Default value for the slashing penalty (50%). It's used if slashingPenalty in storage is 0
    uint public constant DEFAULT_SLASHING_PENALTY = 5000;

    /// @inheritdoc IXSTBL
    uint public constant MIN_VEST = 14 days;

    /// @inheritdoc IXSTBL
    uint public constant MAX_VEST = 180 days;

    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.XSTBL")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant XSTBL_STORAGE_LOCATION = 0x8070df933051cfd06b1bc8a1cc21337087bed1e1452be7055e564e22eadb9e00;

    //region ---------------------------- Data types
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.XSTBL
    struct XstblStorage {
        /// @inheritdoc IXSTBL
        address STBL;
        /// @inheritdoc IXSTBL
        address xStaking;
        /// @inheritdoc IXSTBL
        address revenueRouter;
        /// @dev stores the addresses that are exempt from transfer limitations when transferring out
        EnumerableSet.AddressSet exempt;
        /// @dev stores the addresses that are exempt from transfer limitations when transferring to them
        EnumerableSet.AddressSet exemptTo;
        /// @inheritdoc IXSTBL
        uint pendingRebase;
        /// @inheritdoc IXSTBL
        uint lastDistributedPeriod;
        /// @inheritdoc IXSTBL
        mapping(address => VestPosition[]) vestInfo;
    }
    //endregion ---------------------------- Data types

    //region ---------------------------- Initialization
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function initialize(
        address platform_,
        address stbl_,
        address xStaking_,
        address revenueRouter_
    ) external initializer {
        __Controllable_init(platform_);
        __ERC20_init("xStability", "xSTBL");
        XstblStorage storage $ = _getXSTBLStorage();
        $.STBL = stbl_;
        $.xStaking = xStaking_;
        $.revenueRouter = revenueRouter_;

        $.exempt.add(xStaking_);
        $.exemptTo.add(xStaking_);
    }
    //endregion ---------------------------- Initialization

    //region ---------------------------- Restricted actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IXSTBL
    function rebase() external {
        XstblStorage storage $ = _getXSTBLStorage();

        address _revenueRouter = $.revenueRouter;

        /// @dev gate to minter and call it on epoch flips
        require(msg.sender == _revenueRouter, IncorrectMsgSender());

        /// @dev fetch the current period
        uint period = IRevenueRouter(_revenueRouter).getPeriod();

        uint _pendingRebase = $.pendingRebase;

        /// @dev if it's a new period (epoch)
        if (
            /// @dev if the rebase is greater than the Basis
            period > $.lastDistributedPeriod && _pendingRebase >= BASIS
        ) {
            /// @dev PvP rebase notified to the XStaking contract to stream to xSTBL
            /// @dev fetch the current period from voter
            $.lastDistributedPeriod = period;

            /// @dev zero it out
            $.pendingRebase = 0;

            address _xStaking = $.xStaking;

            /// @dev approve STBL transferring to voteModule
            IERC20($.STBL).approve(_xStaking, _pendingRebase);

            /// @dev notify the STBL rebase
            IXStaking(_xStaking).notifyRewardAmount(_pendingRebase);

            emit Rebase(msg.sender, _pendingRebase);
        }
    }

    /// @inheritdoc IXSTBL
    function setExemptionFrom(address[] calldata exemptee, bool[] calldata exempt) external onlyGovernanceOrMultisig {
        /// @dev ensure arrays of same length
        require(exemptee.length == exempt.length, IncorrectArrayLength());

        XstblStorage storage $ = _getXSTBLStorage();
        EnumerableSet.AddressSet storage exemptFrom = $.exempt;

        /// @dev loop through all and attempt add/remove based on status
        uint len = exempt.length;
        for (uint i; i < len; ++i) {
            bool success = exempt[i] ? exemptFrom.add(exemptee[i]) : exemptFrom.remove(exemptee[i]);
            /// @dev emit : (who, status, success)
            emit ExemptionFrom(exemptee[i], exempt[i], success);
        }
    }

    /// @inheritdoc IXSTBL
    function setExemptionTo(address[] calldata exemptee, bool[] calldata exempt) external onlyGovernanceOrMultisig {
        /// @dev ensure arrays of same length
        require(exemptee.length == exempt.length, IncorrectArrayLength());

        XstblStorage storage $ = _getXSTBLStorage();
        EnumerableSet.AddressSet storage exemptTo = $.exemptTo;

        /// @dev loop through all and attempt add/remove based on status
        uint len = exempt.length;
        for (uint i; i < len; ++i) {
            bool success = exempt[i] ? exemptTo.add(exemptee[i]) : exemptTo.remove(exemptee[i]);
            /// @dev emit : (who, status, success)
            emit ExemptionTo(exemptee[i], exempt[i], success);
        }
    }

    //endregion ---------------------------- Restricted actions

    //region ---------------------------- User actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       USER ACTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IXSTBL
    function enter(uint amount_) external {
        /// @dev ensure the amount_ is > 0
        require(amount_ != 0, IncorrectZeroArgument());
        /// @dev transfer from the caller to this address
        // slither-disable-next-line unchecked-transfer
        IERC20(STBL()).safeTransferFrom(msg.sender, address(this), amount_);
        /// @dev mint the xSTBL to the caller
        _mint(msg.sender, amount_);
        /// @dev emit an event for conversion
        emit Enter(msg.sender, amount_);
    }

    /// @inheritdoc IXSTBL
    function exit(uint amount_) external returns (uint exitedAmount) {
        /// @dev cannot exit a 0 amount
        require(amount_ != 0, IncorrectZeroArgument());

        /// @dev if it's at least 2 wei it will give a penalty
        uint penalty = amount_ * SLASHING_PENALTY() / BASIS;
        uint exitAmount = amount_ - penalty;

        /// @dev burn the xSTBL from the caller's address
        _burn(msg.sender, amount_);

        XstblStorage storage $ = _getXSTBLStorage();

        /// @dev store the rebase earned from the penalty
        $.pendingRebase += penalty;

        /// @dev transfer the exitAmount to the caller
        // slither-disable-next-line unchecked-transfer
        IERC20($.STBL).safeTransfer(msg.sender, exitAmount);

        /// @dev emit actual exited amount
        emit InstantExit(msg.sender, exitAmount);

        return exitAmount;
    }

    /// @inheritdoc IXSTBL
    function createVest(uint amount_) external {
        /// @dev ensure not 0
        require(amount_ != 0, IncorrectZeroArgument());

        /// @dev preemptive burn
        _burn(msg.sender, amount_);

        XstblStorage storage $ = _getXSTBLStorage();

        /// @dev fetch total length of vests
        uint vestLength = $.vestInfo[msg.sender].length;

        /// @dev push new position
        $.vestInfo[msg.sender].push(VestPosition(amount_, block.timestamp, block.timestamp + MAX_VEST, vestLength));

        emit NewVest(msg.sender, vestLength, amount_);
    }

    /// @inheritdoc IXSTBL
    function exitVest(uint vestID_) external {
        XstblStorage storage $ = _getXSTBLStorage();

        VestPosition storage _vest = $.vestInfo[msg.sender][vestID_];
        require(_vest.amount != 0, NO_VEST());

        /// @dev store amount in the vest and start time
        uint _amount = _vest.amount;
        uint _start = _vest.start;

        /// @dev zero out the amount before anything else as a safety measure
        _vest.amount = 0;

        if (block.timestamp < _start + MIN_VEST) {
            /// @dev case: vest has not crossed the minimum vesting threshold
            /// @dev mint cancelled xSTBL back to msg.sender
            _mint(msg.sender, _amount);

            emit CancelVesting(msg.sender, vestID_, _amount);
        } else if (_vest.maxEnd <= block.timestamp) {
            /// @dev case: vest is complete
            /// @dev send liquid STBL to msg.sender
            // slither-disable-next-line unchecked-transfer
            IERC20($.STBL).safeTransfer(msg.sender, _amount);

            emit ExitVesting(msg.sender, vestID_, _amount, _amount);
        } else {
            /// @dev case: vest is in progress
            /// @dev calculate % earned based on length of time that has vested
            /// @dev linear calculations

            /// @dev max possible penalty on the amount
            uint penalty = _amount * SLASHING_PENALTY() / BASIS;

            /// @dev minimum amount that user received at any case
            uint base = _amount - penalty;

            /// @dev calculate the extra earned via vesting
            uint vestEarned = penalty * (block.timestamp - _start) / MAX_VEST;

            uint exitedAmount = base + vestEarned;

            /// @dev add to the existing pendingRebases
            $.pendingRebase += (_amount - exitedAmount);

            /// @dev transfer underlying to the sender after penalties removed
            // slither-disable-next-line unchecked-transfer
            IERC20($.STBL).safeTransfer(msg.sender, exitedAmount);

            emit ExitVesting(msg.sender, vestID_, _amount, exitedAmount);
        }
    }
    //endregion ---------------------------- User actions

    //region ---------------------------- View functions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IXSTBL
    function STBL() public view returns (address) {
        return _getXSTBLStorage().STBL;
    }

    /// @inheritdoc IXSTBL
    // solhint-disable-next-line func-name-mixedcase
    function SLASHING_PENALTY() public view returns (uint) {
        IStabilityDAO stabilityDao = getStabilityDAO();
        return address(stabilityDao) == address(0)
            ? DEFAULT_SLASHING_PENALTY
            : getStabilityDAO().exitPenalty();
    }

    /// @inheritdoc IXSTBL
    function xStaking() external view returns (address) {
        return _getXSTBLStorage().xStaking;
    }

    /// @inheritdoc IXSTBL
    function revenueRouter() external view returns (address) {
        return _getXSTBLStorage().revenueRouter;
    }

    /// @inheritdoc IXSTBL
    function vestInfo(address user, uint vestID) external view returns (uint amount, uint start, uint maxEnd) {
        XstblStorage storage $ = _getXSTBLStorage();
        VestPosition memory vestPosition = $.vestInfo[user][vestID];
        amount = vestPosition.amount;
        start = vestPosition.start;
        maxEnd = vestPosition.maxEnd;
    }

    /// @inheritdoc IXSTBL
    function usersTotalVests(address who) external view returns (uint numOfVests) {
        XstblStorage storage $ = _getXSTBLStorage();
        return $.vestInfo[who].length;
    }

    /// @inheritdoc IXSTBL
    function pendingRebase() external view returns (uint) {
        return _getXSTBLStorage().pendingRebase;
    }

    /// @inheritdoc IXSTBL
    function lastDistributedPeriod() external view returns (uint) {
        return _getXSTBLStorage().lastDistributedPeriod;
    }
    //endregion ---------------------------- View functions

    //region ---------------------------- Hooks to override
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     HOOKS TO OVERRIDE                      */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function _update(address from, address to, uint value) internal override {
        require(_isExempted(from, to), NOT_WHITELISTED(from, to));

        /// @dev call parent function
        super._update(from, to, value);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       INTERNAL LOGIC                       */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev internal check for the transfer whitelist
    function _isExempted(address from_, address to_) internal view returns (bool) {
        XstblStorage storage $ = _getXSTBLStorage();
        return (from_ == address(0) || to_ == address(0) || $.exempt.contains(from_) || $.exemptTo.contains(to_));
    }

    function _getXSTBLStorage() internal pure returns (XstblStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := XSTBL_STORAGE_LOCATION
        }
    }

    function getStabilityDAO() internal view returns (IStabilityDAO) {
        return IStabilityDAO(IPlatform(IControllable(address(this)).platform()).stabilityDAO());
    }
    //endregion ---------------------------- Hooks to override
}
