// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";

contract Vesting {
    using SafeERC20 for IERC20;

    event Released(uint amount);
    event Beneficiary(address beneficiary_);
    event DelayStart(uint64 oldStart, uint64 newSstart);

    // slither-disable-next-line naming-convention
    address public immutable PLATFORM;
    // slither-disable-next-line naming-convention
    address public immutable TOKEN;
    address public beneficiary;
    string public name;
    // slither-disable-next-line naming-convention
    uint64 public immutable DURATION;
    uint64 public start;
    uint public released;

    constructor(address platform_, address token_, string memory name_, uint64 duration_, uint64 start_) {
        PLATFORM = platform_;
        TOKEN = token_;
        name = name_;
        DURATION = duration_;
        start = start_;
    }

    modifier onlyMultisig() {
        _requireMultisig();
        _;
    }

    function setBeneficiary(address beneficiary_) external onlyMultisig {
        beneficiary = beneficiary_;
        emit Beneficiary(beneficiary_);
    }

    function delayStart(uint64 start_) external onlyMultisig {
        require(beneficiary == address(0), "denied");
        emit DelayStart(start, start_);
        start = start_;
    }

    /// @dev Release amount that have already vested
    function release() public virtual {
        require(beneficiary != address(0), "beneficiary is not set yet");
        uint amount = releasable();
        require(amount != 0, "Zero amount");
        released += amount;
        emit Released(amount);
        IERC20(TOKEN).safeTransfer(beneficiary, amount);
    }

    /// @dev Getter for the end timestamp.
    function end() public view virtual returns (uint) {
        return start + DURATION;
    }

    /// @dev Calculates the amount that has already vested
    function vestedAmount(uint64 timestamp) public view virtual returns (uint) {
        return _vestingSchedule(IERC20(TOKEN).balanceOf(address(this)) + released, timestamp);
    }

    /// @dev Getter for the amount of releasable amount
    function releasable() public view virtual returns (uint) {
        return vestedAmount(uint64(block.timestamp)) - released;
    }

    /// @dev Virtual implementation of the vesting formula.
    /// @param totalAllocation Total historical allocation
    /// @param timestamp Time
    /// @return Vested amount
    function _vestingSchedule(uint totalAllocation, uint64 timestamp) internal view virtual returns (uint) {
        if (timestamp < start) {
            return 0;
        } else if (timestamp >= end()) {
            return totalAllocation;
        } else {
            return (totalAllocation * (timestamp - start)) / DURATION;
        }
    }

    function _requireMultisig() internal view {
        require(msg.sender == IPlatform(PLATFORM).multisig(), "denied");
    }
}
