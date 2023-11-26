// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./MockStrategy.sol";
import "../strategies/base/ActiveStrategyBase.sol";

contract MockActiveStrategy is MockStrategy, ActiveStrategyBase {
    bool public mockNeedRebalance;

    function rebalance() external {

    }

    function depositUnderlying(uint amount) public virtual override (MockStrategy, StrategyBase) onlyVault returns(uint[] memory amountsConsumed) {
        return super.depositUnderlying(amount);
    }

    function withdrawUnderlying(uint amount, address receiver) public virtual override (MockStrategy, StrategyBase) onlyVault {
        return super.withdrawUnderlying(amount, receiver);
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override (ActiveStrategyBase, LPStrategyBase) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function getSpecificName() public view override(MockStrategy, StrategyBase) returns (string memory, bool) {
        return super.getSpecificName();
    }

    function swaps() external pure override returns(bool) {
        return false;
    }

    function _beforeDeposit() internal override (ActiveStrategyBase, StrategyBase) {
        super._beforeDeposit();
    }

    function _beforeWithdraw() internal override (ActiveStrategyBase, StrategyBase) {
        super._beforeWithdraw();
    }

    function _beforeDoHardWork() internal override (ActiveStrategyBase, StrategyBase) {
        super._beforeDoHardWork();
    }

    function _needRebalance() internal view override returns (bool) {
        return mockNeedRebalance;
    }
}
