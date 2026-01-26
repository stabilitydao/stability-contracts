// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Controllable} from "../core/base/Controllable.sol";
import {IControllable} from "../interfaces/IControllable.sol";
import {IXToken} from "../interfaces/IXToken.sol";
import {IXStaking} from "../interfaces/IXStaking.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IRevenueRouter} from "../interfaces/IRevenueRouter.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IDAO} from "../interfaces/IDAO.sol";

/// @title XToken - staked version of main token (i.e. STBL)
/// Inspired by xRAM/xSHADOW from Ramses/Shadow codebase
/// @author Alien Deployer (https://github.com/a17)
/// @author Jude (https://github.com/iammrjude)
/// @author Omriss (https://github.com/omriss)
/// Changelog:
///  1.2.0: add list of bridges, sendToBridge, takeFromBridge - #424
///         renaming XSTBL to XToken; params name and symbol were added to initialize() - #426
///         Add setName and setSymbol functions.
///  1.1.0: add possibility to change the slashing penalty value - #406
///  1.0.1: use SafeERC20.safeTransfer/safeTransferFrom instead of ERC20 transfer/transferFrom
contract XToken is Controllable, ERC20Upgradeable, IXToken {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         CONSTANTS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IControllable
    string public constant VERSION = "1.2.0";

    /// @inheritdoc IXToken
    uint public constant BASIS = 10_000;

    /// @notice Default value for the slashing penalty (50%). It's used if slashingPenalty in storage is 0
    uint public constant DEFAULT_SLASHING_PENALTY = 5_000;

    /// @inheritdoc IXToken
    uint public constant MIN_VEST = 14 days;

    /// @inheritdoc IXToken
    uint public constant MAX_VEST = 180 days;

    /// @dev Name "erc7201:stability.XSTBL" is used historically
    // keccak256(abi.encode(uint256(keccak256("erc7201:stability.XSTBL")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant XTOKEN_STORAGE_LOCATION =
        0x8070df933051cfd06b1bc8a1cc21337087bed1e1452be7055e564e22eadb9e00;

    //region ---------------------------- Data types
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                         DATA TYPES                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @custom:storage-location erc7201:stability.XSTBL
    struct XTokenStorage {
        /// @inheritdoc IXToken
        address token;
        /// @inheritdoc IXToken
        address xStaking;
        /// @inheritdoc IXToken
        address revenueRouter;
        /// @dev stores the addresses that are exempt from transfer limitations when transferring out
        EnumerableSet.AddressSet exempt;
        /// @dev stores the addresses that are exempt from transfer limitations when transferring to them
        EnumerableSet.AddressSet exemptTo;
        /// @inheritdoc IXToken
        uint pendingRebase;
        /// @inheritdoc IXToken
        uint lastDistributedPeriod;
        /// @inheritdoc IXToken
        mapping(address => VestPosition[]) vestInfo;
        /// @dev addresses that are allowed to call transferToBridge
        mapping(address => bool) bridges;
        /// @dev Changed ERC20 name
        string changedName;
        /// @dev Changed ERC20 symbol
        string changedSymbol;
    }
    //endregion ---------------------------- Data types

    //region ---------------------------- Initialization
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      INITIALIZATION                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    function initialize(
        address platform_,
        address token_,
        address xStaking_,
        address revenueRouter_,
        string memory name_,
        string memory symbol_
    ) external initializer {
        __Controllable_init(platform_);
        __ERC20_init(name_, symbol_); // i.e. "xStability", "xSTBL"
        XTokenStorage storage $ = _getXTokenStorage();
        $.token = token_;
        $.xStaking = xStaking_;
        $.revenueRouter = revenueRouter_;

        $.exempt.add(xStaking_);
        $.exemptTo.add(xStaking_);
    }

    modifier onlyBridge() {
        _onlyBridge();
        _;
    }

    function _onlyBridge() internal view {
        require(_getXTokenStorage().bridges[msg.sender], IncorrectMsgSender());
    }

    //endregion ---------------------------- Initialization

    //region ---------------------------- Restricted actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      RESTRICTED ACTIONS                    */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IXToken
    function rebase() external {
        XTokenStorage storage $ = _getXTokenStorage();

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
            /// @dev PvP rebase notified to the XStaking contract to stream to xToken
            /// @dev fetch the current period from voter
            $.lastDistributedPeriod = period;

            /// @dev zero it out
            $.pendingRebase = 0;

            address _xStaking = $.xStaking;

            /// @dev approve main-token transferring to voteModule
            IERC20($.token).approve(_xStaking, _pendingRebase);

            /// @dev notify the main-token rebase
            IXStaking(_xStaking).notifyRewardAmount(_pendingRebase);

            emit Rebase(msg.sender, _pendingRebase);
        }
    }

    /// @inheritdoc IXToken
    function setExemptionFrom(address[] calldata exemptee, bool[] calldata exempt) external onlyGovernanceOrMultisig {
        /// @dev ensure arrays of same length
        require(exemptee.length == exempt.length, IncorrectArrayLength());

        XTokenStorage storage $ = _getXTokenStorage();
        EnumerableSet.AddressSet storage exemptFrom = $.exempt;

        /// @dev loop through all and attempt add/remove based on status
        uint len = exempt.length;
        for (uint i; i < len; ++i) {
            bool success = exempt[i] ? exemptFrom.add(exemptee[i]) : exemptFrom.remove(exemptee[i]);
            /// @dev emit : (who, status, success)
            emit ExemptionFrom(exemptee[i], exempt[i], success);
        }
    }

    /// @inheritdoc IXToken
    function setExemptionTo(address[] calldata exemptee, bool[] calldata exempt) external onlyGovernanceOrMultisig {
        /// @dev ensure arrays of same length
        require(exemptee.length == exempt.length, IncorrectArrayLength());

        XTokenStorage storage $ = _getXTokenStorage();
        EnumerableSet.AddressSet storage exemptTo = $.exemptTo;

        /// @dev loop through all and attempt add/remove based on status
        uint len = exempt.length;
        for (uint i; i < len; ++i) {
            bool success = exempt[i] ? exemptTo.add(exemptee[i]) : exemptTo.remove(exemptee[i]);
            /// @dev emit : (who, status, success)
            emit ExemptionTo(exemptee[i], exempt[i], success);
        }
    }

    /// @inheritdoc IXToken
    function setBridge(address bridge_, bool status_) external onlyGovernanceOrMultisig {
        XTokenStorage storage $ = _getXTokenStorage();
        $.bridges[bridge_] = status_;
    }

    /// @inheritdoc IXToken
    function setName(string calldata newName) external onlyOperator {
        XTokenStorage storage $ = _getXTokenStorage();
        $.changedName = newName;
        emit XTokenName(newName);
    }

    /// @inheritdoc IXToken
    function setSymbol(string calldata newSymbol) external onlyOperator {
        XTokenStorage storage $ = _getXTokenStorage();
        $.changedSymbol = newSymbol;
        emit XTokenSymbol(newSymbol);
    }

    //endregion ---------------------------- Restricted actions

    //region ---------------------------- User actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       USER ACTIONS                         */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IXToken
    function enter(uint amount_) external {
        /// @dev ensure the amount_ is > 0
        require(amount_ != 0, IncorrectZeroArgument());
        /// @dev transfer from the caller to this address
        // slither-disable-next-line unchecked-transfer
        IERC20(token()).safeTransferFrom(msg.sender, address(this), amount_);
        /// @dev mint the xToken to the caller
        _mint(msg.sender, amount_);
        /// @dev emit an event for conversion
        emit Enter(msg.sender, amount_);
    }

    /// @inheritdoc IXToken
    function exit(uint amount_) external returns (uint exitedAmount) {
        /// @dev cannot exit a 0 amount
        require(amount_ != 0, IncorrectZeroArgument());

        /// @dev if it's at least 2 wei it will give a penalty
        uint penalty = amount_ * SLASHING_PENALTY() / BASIS;
        uint exitAmount = amount_ - penalty;

        /// @dev burn the xToken from the caller's address
        _burn(msg.sender, amount_);

        XTokenStorage storage $ = _getXTokenStorage();

        /// @dev store the rebase earned from the penalty
        $.pendingRebase += penalty;

        /// @dev transfer the exitAmount to the caller
        // slither-disable-next-line unchecked-transfer
        IERC20($.token).safeTransfer(msg.sender, exitAmount);

        /// @dev emit actual exited amount
        emit InstantExit(msg.sender, exitAmount);

        return exitAmount;
    }

    /// @inheritdoc IXToken
    function createVest(uint amount_) external {
        /// @dev ensure not 0
        require(amount_ != 0, IncorrectZeroArgument());

        /// @dev preemptive burn
        _burn(msg.sender, amount_);

        XTokenStorage storage $ = _getXTokenStorage();

        /// @dev fetch total length of vests
        uint vestLength = $.vestInfo[msg.sender].length;

        /// @dev push new position
        $.vestInfo[msg.sender]
        .push(
            VestPosition({
                amount: amount_, start: block.timestamp, maxEnd: block.timestamp + MAX_VEST, vestID: vestLength
            })
        );

        emit NewVest(msg.sender, vestLength, amount_);
    }

    /// @inheritdoc IXToken
    function exitVest(uint vestID_) external {
        XTokenStorage storage $ = _getXTokenStorage();

        VestPosition storage _vest = $.vestInfo[msg.sender][vestID_];
        require(_vest.amount != 0, NO_VEST());

        /// @dev store amount in the vest and start time
        uint _amount = _vest.amount;
        uint _start = _vest.start;

        /// @dev zero out the amount before anything else as a safety measure
        _vest.amount = 0;

        if (block.timestamp < _start + MIN_VEST) {
            /// @dev case: vest has not crossed the minimum vesting threshold
            /// @dev mint cancelled xToken back to msg.sender
            _mint(msg.sender, _amount);

            emit CancelVesting(msg.sender, vestID_, _amount);
        } else if (_vest.maxEnd <= block.timestamp) {
            /// @dev case: vest is complete
            /// @dev send liquid main-token to msg.sender
            // slither-disable-next-line unchecked-transfer
            IERC20($.token).safeTransfer(msg.sender, _amount);

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
            IERC20($.token).safeTransfer(msg.sender, exitedAmount);

            emit ExitVesting(msg.sender, vestID_, _amount, exitedAmount);
        }
    }

    //endregion ---------------------------- User actions

    //region ---------------------------- Bridge actions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                     BRIDGES ACTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IXToken
    function sendToBridge(address user_, uint amount_) external onlyBridge {
        XTokenStorage storage $ = _getXTokenStorage();
        require(amount_ != 0 && user_ != address(0), IncorrectZeroArgument());

        /// @dev burn the xToken from the caller's address
        _burn(user_, amount_);

        /// @dev Send main-token back to the caller (bridge)
        IERC20($.token).safeTransfer(msg.sender, amount_);

        emit SendToBridge(user_, amount_);
    }

    /// @inheritdoc IXToken
    function takeFromBridge(address user_, uint amount_) external onlyBridge {
        require(amount_ != 0 && user_ != address(0), IncorrectZeroArgument());

        /// @dev transfer from the bridge to this address
        IERC20(token()).safeTransferFrom(msg.sender, address(this), amount_);

        /// @dev mint the xToken to the user address
        _mint(user_, amount_);

        /// @dev emit an event for conversion
        emit ReceivedFromBridge(user_, amount_);
    }

    //endregion ---------------------------- Bridge actions

    //region ---------------------------- View functions
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      VIEW FUNCTIONS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @inheritdoc IXToken
    function token() public view returns (address) {
        return _getXTokenStorage().token;
    }

    /// @inheritdoc IXToken
    // solhint-disable-next-line func-name-mixedcase
    function SLASHING_PENALTY() public view returns (uint) {
        IDAO dao = getDAO();
        if (address(dao) != address(0)) {
            uint penalty = getDAO().exitPenalty();

            // @dev 0 penalty means that default value should be used
            if (penalty != 0) return penalty;
        }

        return DEFAULT_SLASHING_PENALTY;
    }

    /// @inheritdoc IXToken
    function xStaking() external view returns (address) {
        return _getXTokenStorage().xStaking;
    }

    /// @inheritdoc IXToken
    function revenueRouter() external view returns (address) {
        return _getXTokenStorage().revenueRouter;
    }

    /// @inheritdoc IXToken
    function vestInfo(address user, uint vestID) external view returns (uint amount, uint start, uint maxEnd) {
        XTokenStorage storage $ = _getXTokenStorage();
        VestPosition memory vestPosition = $.vestInfo[user][vestID];
        amount = vestPosition.amount;
        start = vestPosition.start;
        maxEnd = vestPosition.maxEnd;
    }

    /// @inheritdoc IXToken
    function usersTotalVests(address who) external view returns (uint numOfVests) {
        XTokenStorage storage $ = _getXTokenStorage();
        return $.vestInfo[who].length;
    }

    /// @inheritdoc IXToken
    function pendingRebase() external view returns (uint) {
        return _getXTokenStorage().pendingRebase;
    }

    /// @inheritdoc IXToken
    function lastDistributedPeriod() external view returns (uint) {
        return _getXTokenStorage().lastDistributedPeriod;
    }

    /// @inheritdoc IXToken
    function isBridge(address bridge_) external view returns (bool) {
        return _getXTokenStorage().bridges[bridge_];
    }

    /// @inheritdoc ERC20Upgradeable
    function name() public view override returns (string memory) {
        XTokenStorage storage $ = _getXTokenStorage();
        string memory changedName = $.changedName;
        if (bytes(changedName).length != 0) {
            return changedName;
        }
        return super.name();
    }

    /// @inheritdoc ERC20Upgradeable
    function symbol() public view override returns (string memory) {
        XTokenStorage storage $ = _getXTokenStorage();
        string memory changedSymbol = $.changedSymbol;
        if (bytes(changedSymbol).length != 0) {
            return changedSymbol;
        }
        return super.symbol();
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
        XTokenStorage storage $ = _getXTokenStorage();
        return (from_ == address(0) || to_ == address(0) || $.exempt.contains(from_) || $.exemptTo.contains(to_));
    }

    function _getXTokenStorage() internal pure returns (XTokenStorage storage $) {
        //slither-disable-next-line assembly
        assembly {
            $.slot := XTOKEN_STORAGE_LOCATION
        }
    }

    function getDAO() internal view returns (IDAO) {
        return IDAO(IPlatform(IControllable(address(this)).platform()).stabilityDAO());
    }
    //endregion ---------------------------- Hooks to override
}
