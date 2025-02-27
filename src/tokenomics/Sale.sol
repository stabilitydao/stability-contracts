// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";
import {IMintedERC20} from "../interfaces/IMintedERC20.sol";
import {IBurnableERC20} from "../interfaces/IBurnableERC20.sol";

/// @title Token sale
/// @author Alien Deployer (https://github.com/a17)
contract Sale {
    using SafeERC20 for IERC20;

    uint public constant ALLOCATION_SALE = 4_000_000 * 10 ** 18;

    address public platform;
    address public token;
    address public receiptToken;
    address public spendToken;
    uint public price;
    uint public sold;
    uint64 public start;
    uint64 public end;
    uint64 public tge;
    mapping(address user => uint bought) public bought;

    constructor(address platform_, address spendToken_, uint price_, uint64 start_, uint64 end_, uint64 tge_) {
        platform = platform_;
        spendToken = spendToken_;
        price = price_;
        start = start_;
        end = end_;
        tge = tge_;
    }

    modifier onlyOperator() {
        _requireOperator();
        _;
    }

    function setupReceiptToken(address receiptToken_) external onlyOperator {
        require(receiptToken == address(0), "already");
        receiptToken = receiptToken_;
    }

    function setupToken(address token_) external onlyOperator {
        require(token == address(0), "already");
        require(IERC20(token_).balanceOf(address(this)) == ALLOCATION_SALE, "incorrect supply");
        token = token_;
    }

    function setupDates(uint64 start_, uint64 end_, uint64 tge_) external onlyOperator {
        require(block.timestamp < tge || token == address(0), "Cant change");
        start = start_;
        end = end_;
        tge = tge_;
    }

    function burnNotSold() external onlyOperator {
        address _token = token;
        require(_token != address(0) && block.timestamp >= tge, "Wait for TGE");
        uint toBurn = ALLOCATION_SALE - sold;
        require(toBurn != 0, "All sold");
        IBurnableERC20(_token).burn(toBurn);
    }

    function buy(uint amount) external {
        require(block.timestamp >= start, "Sale is not started yet");
        require(block.timestamp < end, "Sale ended");
        require(sold + amount <= ALLOCATION_SALE, "Too much");
        uint totalBought = bought[msg.sender];
        require(totalBought + amount <= ALLOCATION_SALE / 10, "Too much for user");
        uint toSpend = amount * price / 1e18;
        require(toSpend > 0, "Zero amount");
        sold += amount;
        IERC20(spendToken).safeTransferFrom(msg.sender, IPlatform(platform).multisig(), toSpend);
        IMintedERC20(receiptToken).mint(msg.sender, amount);
        bought[msg.sender] = totalBought + amount;
    }

    function claim() external {
        uint userBalance = IERC20(receiptToken).balanceOf(msg.sender);
        require(userBalance > 0, "You dont have not claimed tokens");
        address _token = token;
        require(_token != address(0) && block.timestamp >= tge, "Wait for TGE");
        IERC20(receiptToken).safeTransferFrom(msg.sender, address(this), userBalance);
        IBurnableERC20(receiptToken).burn(userBalance);
        IERC20(_token).safeTransfer(msg.sender, userBalance);
    }

    function _requireOperator() internal view {
        require(IPlatform(platform).isOperator(msg.sender), "denied");
    }
}
