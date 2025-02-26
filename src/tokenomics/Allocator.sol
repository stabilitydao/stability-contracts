// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPlatform} from "../interfaces/IPlatform.sol";

contract Allocator {
    using SafeERC20 for IERC20;

    uint public constant ALLOCATION_SALE = 4_000_000 * 1e18;
    uint public constant ALLOCATION_LIQUIDITY = 6_000_000 * 1e18;
    uint public constant ALLOCATION_INVESTORS = 20_000_000 * 1e18;
    uint public constant ALLOCATION_FOUNDATION = 30_000_000 * 1e18;
    uint public constant ALLOCATION_COMMUNITY_UNLOCKED = 28_000 * 1e18;
    uint public constant ALLOCATION_COMMUNITY = 20_000_000 * 1e18 - ALLOCATION_COMMUNITY_UNLOCKED;
    uint public constant ALLOCATION_TEAM = 20_000_000 * 1e18;

    address public platform;

    constructor(address platform_) {
        platform = platform_;
    }

    function allocate(
        address token,
        address sale,
        address investors,
        address foundation,
        address community,
        address team
    ) external {
        require(IPlatform(platform).isOperator(msg.sender), "denied");
        require(IERC20(token).balanceOf(address(this)) == 100_000_000 * 10 ** 18, "error");

        IERC20(token).safeTransfer(sale, ALLOCATION_SALE);
        IERC20(token).safeTransfer(IPlatform(platform).multisig(), ALLOCATION_LIQUIDITY + ALLOCATION_COMMUNITY_UNLOCKED);
        IERC20(token).safeTransfer(investors, ALLOCATION_INVESTORS);
        IERC20(token).safeTransfer(foundation, ALLOCATION_FOUNDATION);
        IERC20(token).safeTransfer(community, ALLOCATION_COMMUNITY);
        IERC20(token).safeTransfer(team, ALLOCATION_TEAM);
    }
}
